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
    @Published private(set) var chunkMs: Double = 0   // ก้อนใหญ่สุดที่ไมค์ส่งมาใน ~50 ms ล่าสุด

    // ทางเลือกสำรอง: ถ้า true จะ bind แค่ 127.0.0.1 (ใช้เมื่อ usbmux ต่อ port ไม่ได้)
    private let bindLoopbackOnly = false

    private let port: NWEndpoint.Port = 7777
    private let sampleRate: Double = 48000
    private let queue = DispatchQueue(label: "ipadmic.mic")
    private let engine = AVAudioEngine()
    private var sink: AVAudioSinkNode?

    // เขียนจาก main อ่านจากเธรดเสียง (ค่าเดียว ไม่ต้องล็อก)
    private var gain: Float = 1
    private var muted = false
    func setGain(db: Double) { gain = Float(pow(10, db / 20)) }
    func setMuted(_ m: Bool) { muted = m }

    private var listener: NWListener?
    private var connection: NWConnection?
    private var ready = false      // header ส่งแล้ว ส่ง PCM ได้
    private var inFlight = 0       // ก้อนที่ส่งแล้วแต่ระบบยังไม่ตอบรับ กัน memory โตถ้า PC อ่านไม่ทัน

    // ใช้เฉพาะใน sink callback (เธรดเสียงเธรดเดียว) สำหรับหน่วงการอัปเดต UI
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

    /// raw = true: .measurement (ไม่มี auto gain/แต่งเสียง) ทดสอบจริงแล้วเบาและทึบ จึงไม่ใช่ค่าเริ่มต้น
    func start(raw: Bool) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard let self = self else { return }
            self.queue.async {
                if granted { self.startOnQueue(raw: raw) } else { self.setState(.error("ไม่ได้รับอนุญาตใช้ไมค์")) }
            }
        }
    }

    private func startOnQueue(raw: Bool) {
        guard listener == nil else { return }
        do {
            try startEngine(raw: raw)
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

    /// AVAudioSession .record (โหมดมาตรฐานหรือดิบ) แล้วต่อ sink node จาก inputNode
    private func startEngine(raw: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: raw ? .measurement : .default)
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
        // ใช้ sink node แทน installTap: tap ส่งก้อนละ 100 ms ตายตัว (วัดจริงบน iPad)
        // sink ได้ก้อนตาม IO buffer ของฮาร์ดแวร์ (ขอไว้ 5 ms) → latency ต่ำ
        let newSink = AVAudioSinkNode { [weak self] _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: abl))
            // format มาตรฐานของ inputNode เป็น non-interleaved: buffers[0] = channel 0
            if let p = buffers.first?.mData {
                self?.handle(p.assumingMemoryBound(to: Float.self), Int(frameCount))
            }
            return noErr
        }
        engine.attach(newSink)
        engine.connect(input, to: newSink, format: format)
        sink = newSink
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
        engine.stop()
        if let s = sink {
            engine.detach(s)
            sink = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false)
        DispatchQueue.main.async { self.level = 0 }
    }

    // MARK: - เสียงจากไมค์ (เรียกจากเธรดเสียง ห้ามบล็อก)

    private func handle(_ ch: UnsafePointer<Float>, _ n: Int) {
        guard n > 0 else { return }
        // ปิดไมค์ = ส่งเสียงเงียบ (ไม่ตัดสาย) ตัวรับไม่ต้องต่อใหม่ DAW ไม่สะดุด
        let g = muted ? 0 : gain
        var out = [Float](repeating: 0, count: n)
        var peak: Float = 0
        if g > 0 {
            for i in 0..<n {
                let v = max(-1, min(1, ch[i] * g))   // clip ที่ ±1 เหมือนที่ตัวรับจะได้
                out[i] = v
                peak = max(peak, abs(v))
            }
        }
        uiPeak = max(uiPeak, peak)
        uiChunk = max(uiChunk, Double(n) / sampleRate * 1000)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastUI >= 0.05 {
            lastUI = now
            let p = uiPeak, c = uiChunk
            uiPeak = 0; uiChunk = 0
            DispatchQueue.main.async { self.level = p; self.chunkMs = c }
        }
        let data = out.withUnsafeBufferPointer { Data(buffer: $0) }
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
