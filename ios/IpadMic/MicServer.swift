import AVFoundation
import Foundation
import Network

struct MicError: Error { let message: String }

/// เซิร์ฟเวอร์ TCP พอร์ต 7777 ส่งเสียงไมค์เป็น Float32 mono 48 kHz
/// โปรโตคอลต้องตรงกับ windows/receiver.py ทุก byte (ดู docs/GUIDE.md)
final class MicServer: ObservableObject {
    enum State: Equatable { case stopped, waiting, streaming, interrupted, error(String) }

    // อัปเดตผ่าน setState เท่านั้น เพื่อให้ขึ้น main thread เสมอ (SwiftUI ห้ามแก้จากเธรดอื่น)
    @Published private(set) var state: State = .stopped
    @Published private(set) var level: Float = 0      // peak 0...1 ใน ~50 ms ล่าสุด
    @Published private(set) var chunkMs: Double = 0   // ก้อนใหญ่สุดที่ tap ส่งมาใน ~50 ms ล่าสุด

    // ทางเลือกสำรอง: ถ้า true จะ bind แค่ 127.0.0.1 (ใช้เมื่อ usbmux ต่อ port ไม่ได้)
    private let bindLoopbackOnly = false

    private let port: NWEndpoint.Port = 7777
    private let sampleRate: Double = 48000
    private let queue = DispatchQueue(label: "ipadmic.mic")
    private let engine = AVAudioEngine()

    private var listener: NWListener?
    private var connection: NWConnection?
    private var ready = false      // header ส่งแล้ว ส่ง PCM ได้
    private var inFlight = 0       // ก้อนที่ส่งแล้วแต่ระบบยังไม่ตอบรับ กัน memory โตถ้า PC อ่านไม่ทัน

    // ใช้เฉพาะใน tap callback (เธรดเดียว) สำหรับหน่วงการอัปเดต UI
    private var lastUI = 0.0
    private var uiPeak: Float = 0
    private var uiChunk = 0.0

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { self?.interrupt() }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
            // .categoryChange ฯลฯ ยิงตอนเริ่ม session ด้วย จึงสนใจแค่ไมค์ถูกถอด/เสียบ
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                || raw == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                self?.interrupt()
            }
        }
    }

    private func setState(_ new: State) {
        DispatchQueue.main.async { self.state = new }
    }

    // MARK: - start / stop

    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            self.queue.async {
                if granted { self.startOnQueue() } else { self.setState(.error("ไม่ได้รับอนุญาตใช้ไมค์")) }
            }
        }
    }

    private func startOnQueue() {
        guard listener == nil else { return }
        do {
            try startEngine()
            try startListener()
            setState(.waiting)
        } catch let e as MicError {
            teardown()
            setState(.error(e.message))
        } catch {
            teardown()
            setState(.error(error.localizedDescription))
        }
    }

    /// AVAudioSession .record + .measurement (ไม่ประมวลผลเสียง) แล้วต่อ tap จาก inputNode
    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        guard session.sampleRate == sampleRate else {
            throw MicError(message: "iPad ให้ \(Int(session.sampleRate)) Hz ไม่ใช่ 48000")
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate == sampleRate else {
            throw MicError(message: "ไมค์ให้ \(Int(format.sampleRate)) Hz ไม่ใช่ 48000")
        }
        // bufferSize เป็นแค่คำขอ iOS อาจส่งก้อนใหญ่กว่านี้ ดู chunkMs บนจอ
        input.installTap(onBus: 0, bufferSize: 480, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func startListener() throws {
        let params = NWParameters.tcp
        // ปิด Nagle: ไม่ให้ระบบหน่วงรอรวมก้อนเล็ก ๆ ไม่งั้นเสียงจะมี latency และกระตุก
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true
        let newListener: NWListener
        if bindLoopbackOnly {
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            newListener = try NWListener(using: params)
        } else {
            newListener = try NWListener(using: params, on: port)
        }
        newListener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        newListener.start(queue: queue)
        listener = newListener
    }

    func stop() {
        queue.async {
            self.teardown()
            self.setState(.stopped)
        }
    }

    private func interrupt() {
        queue.async {
            guard self.listener != nil else { return }
            self.teardown()
            self.setState(.interrupted)
        }
    }

    private func teardown() {
        dropConnection()
        listener?.cancel()
        listener = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        DispatchQueue.main.async { self.level = 0 }
    }

    // MARK: - เสียงจากไมค์ (เรียกจากเธรดเสียง ห้ามบล็อก)

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let n = Int(buffer.frameLength)
        guard n > 0, let ch = buffer.floatChannelData?[0] else { return }   // เอาแค่ channel 0
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(ch[i])) }
        uiPeak = max(uiPeak, peak)
        uiChunk = max(uiChunk, Double(n) / sampleRate * 1000)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastUI >= 0.05 {
            lastUI = now
            let p = uiPeak, c = uiChunk
            uiPeak = 0; uiChunk = 0
            DispatchQueue.main.async { self.level = p; self.chunkMs = c }
        }
        let data = Data(bytes: ch, count: n * MemoryLayout<Float>.size)
        queue.async { self.send(data) }
    }

    /// ไม่มี client = ทิ้ง sample (engine ยังรันอยู่ เพื่อไม่ให้แอปถูก suspend ตอนล็อกจอ)
    private func send(_ data: Data) {
        guard ready, let conn = connection, inFlight < 100 else { return }
        inFlight += 1
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            self.inFlight -= 1
            if error != nil { self.backToWaiting() }
        })
    }

    // MARK: - TCP

    private func accept(_ conn: NWConnection) {
        // ให้ PC ต่อซ้ำได้: ทิ้งตัวเก่าก่อนรับตัวใหม่
        dropConnection()
        connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] s in
            guard let self = self, let conn = conn, self.connection === conn else { return }
            switch s {
            case .ready:
                self.sendHeader(on: conn)
                self.ready = true
                self.setState(.streaming)
            case .failed, .cancelled:
                self.backToWaiting()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    /// header 16 byte little-endian: "IPMC" | ver u16=1 | ch u16=1 | rate u32=48000 | fmt u16=1 | rsv u16=0
    private func sendHeader(on conn: NWConnection) {
        var d = Data("IPMC".utf8)
        func put<T: FixedWidthInteger>(_ v: T) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
        }
        put(UInt16(1)); put(UInt16(1)); put(UInt32(48000)); put(UInt16(1)); put(UInt16(0))
        conn.send(content: d, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.backToWaiting() }
        })
    }

    private func dropConnection() {
        ready = false
        inFlight = 0
        connection?.cancel()
        connection = nil
    }

    private func backToWaiting() {
        dropConnection()
        if listener != nil { setState(.waiting) }
    }
}
