import Foundation
import Network

/// เซิร์ฟเวอร์ TCP พอร์ต 7777 ส่ง sine 440 Hz เป็น Float32 mono 48 kHz
/// โปรโตคอลต้องตรงกับ windows/spike_receiver.py ทุก byte (ดู docs/GUIDE.md)
final class SineServer: ObservableObject {
    enum State { case stopped, waiting, streaming }

    // อัปเดตผ่าน setState เท่านั้น เพื่อให้ขึ้น main thread เสมอ (SwiftUI ห้ามแก้จากเธรดอื่น)
    @Published private(set) var state: State = .stopped

    // ทางเลือกสำรอง: ถ้า true จะ bind แค่ 127.0.0.1 (ใช้เมื่อ usbmux ต่อ port ไม่ได้)
    private let bindLoopbackOnly = false

    private let port: NWEndpoint.Port = 7777
    private let sampleRate: Double = 48000
    private let frequency: Double = 440
    private let samplesPerChunk = 480          // 10 ms ที่ 48 kHz
    private let queue = DispatchQueue(label: "ipadmic.sine")

    private var listener: NWListener?
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?

    // phase ต้องเก็บข้ามก้อนและต่อเนื่อง ถ้าเริ่มจาก 0 ทุกก้อนจะเกิดรอยกระโดด
    // ได้ยินเป็นเสียงคลิกทุก 10 ms
    private var phase: Double = 0

    private func setState(_ new: State) {
        DispatchQueue.main.async { self.state = new }
    }

    func start() {
        queue.async { self.startOnQueue() }
    }

    private func startOnQueue() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        // ปิด Nagle: ไม่ให้ระบบหน่วงรอรวมก้อนเล็ก ๆ ไม่งั้นเสียงจะมี latency และกระตุก
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true

        do {
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
            setState(.waiting)
        } catch {
            setState(.stopped)
        }
    }

    private func accept(_ conn: NWConnection) {
        // ให้ PC ต่อซ้ำได้: ทิ้งตัวเก่าก่อนรับตัวใหม่
        dropConnection()
        connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] s in
            guard let self = self, let conn = conn, self.connection === conn else { return }
            switch s {
            case .ready:
                self.sendHeader(on: conn)
                self.startTimer()
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

    private func startTimer() {
        phase = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.sendChunk() }
        t.resume()
        timer = t
    }

    private func sendChunk() {
        guard let conn = connection else { return }
        let step = 2.0 * Double.pi * frequency / sampleRate
        var samples = [Float](repeating: 0, count: samplesPerChunk)
        for i in 0..<samplesPerChunk {
            samples[i] = Float(0.5 * sin(phase))
            phase += step
        }
        // wrap เพื่อกัน phase โตไม่จำกัดแล้วความแม่นยำของ Double ลดลงเมื่อรันนาน
        phase = fmod(phase, 2.0 * Double.pi)

        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.backToWaiting() }
        })
    }

    private func dropConnection() {
        timer?.cancel()
        timer = nil
        connection?.cancel()
        connection = nil
    }

    private func backToWaiting() {
        dropConnection()
        if listener != nil { setState(.waiting) }
    }

    func stop() {
        queue.async {
            self.dropConnection()
            self.listener?.cancel()
            self.listener = nil
            self.setState(.stopped)
        }
    }
}
