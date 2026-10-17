import Foundation

// เอฟเฟกต์เสียงที่เรียกจากเธรดเสียงทีละ sample ห้ามจองหน่วยความจำตอนทำงาน
// ค่าตั้ง (coefficient, preset) เขียนจาก main อ่านจากเธรดเสียงโดยไม่ล็อก
// shortcut: ตอนเปลี่ยนค่าอาจได้ coefficient ครึ่งเก่าครึ่งใหม่ 1 sample (คลิกเบามาก) ถ้าได้ยินให้ส่งค่าผ่าน atomic swap

/// biquad สูตร RBJ Audio EQ Cookbook แบบ transposed direct form II
final class Biquad {
    var enabled = true
    private var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    private var z1: Float = 0, z2: Float = 0

    func process(_ x: Float) -> Float {
        guard enabled else { return x }
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    func setHighPass(freq: Double, rate: Double = 48000, q: Double = 0.707) {
        let w = 2 * Double.pi * freq / rate
        let alpha = sin(w) / (2 * q), c = cos(w)
        set(b: [(1 + c) / 2, -(1 + c), (1 + c) / 2], a: [1 + alpha, -2 * c, 1 - alpha])
    }

    func setPeaking(freq: Double, gainDB: Double, rate: Double = 48000, q: Double = 1.0) {
        let A = pow(10, gainDB / 40)
        let w = 2 * Double.pi * freq / rate
        let alpha = sin(w) / (2 * q), c = cos(w)
        set(b: [1 + alpha * A, -2 * c, 1 - alpha * A], a: [1 + alpha / A, -2 * c, 1 - alpha / A])
    }

    private func set(b: [Double], a: [Double]) {
        b0 = Float(b[0] / a[0]); b1 = Float(b[1] / a[0]); b2 = Float(b[2] / a[0])
        a1 = Float(a[1] / a[0]); a2 = Float(a[2] / a[0])
    }
}

/// reverb แบบ Freeverb (Jezar) mono: comb 8 ตัวขนานกัน แล้วผ่าน allpass 4 ตัว ไม่เพิ่มดีเลย์
final class Reverb {
    enum Preset: Int { case off = 0, room = 1, hall = 2 }

    var preset: Preset = .off { didSet { apply() } }
    var mix: Float = 0.2               // 0...0.5 สัดส่วนเสียงก้องที่ผสมเข้าไป

    private struct Comb {
        var buf: [Float]; var idx = 0; var store: Float = 0
        init(_ n: Int) { buf = [Float](repeating: 0, count: n) }
        mutating func process(_ x: Float, feedback: Float, damp: Float) -> Float {
            let out = buf[idx]
            store = out * (1 - damp) + store * damp
            buf[idx] = x + store * feedback
            idx += 1; if idx == buf.count { idx = 0 }
            return out
        }
    }
    private struct Allpass {
        var buf: [Float]; var idx = 0
        init(_ n: Int) { buf = [Float](repeating: 0, count: n) }
        mutating func process(_ x: Float) -> Float {
            let b = buf[idx]
            buf[idx] = x + b * 0.5
            idx += 1; if idx == buf.count { idx = 0 }
            return b - x
        }
    }

    // ความยาวของ Freeverb ต้นฉบับ (44.1 kHz) ขยายเป็น 48 kHz
    private var combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map { Comb($0 * 480 / 441) }
    private var allpasses = [556, 441, 341, 225].map { Allpass($0 * 480 / 441) }
    private var feedback: Float = 0.84
    private var damp: Float = 0.2

    private func apply() {
        switch preset {
        case .off: break
        case .room: feedback = 0.7 + 0.28 * 0.5; damp = 0.4 * 0.5    // ห้องเล็ก หางสั้น
        case .hall: feedback = 0.7 + 0.28 * 0.85; damp = 0.4 * 0.3   // ฮอลล์ หางยาว สว่างกว่า
        }
    }

    func process(_ x: Float) -> Float {
        guard preset != .off else { return x }
        let input = x * 0.015                // fixed gain ของ Freeverb กันผลรวม comb ล้น
        var wet: Float = 0
        for i in 0..<combs.count { wet += combs[i].process(input, feedback: feedback, damp: damp) }
        for i in 0..<allpasses.count { wet = allpasses[i].process(wet) }
        return x + wet * 3 * mix             // 3 = scalewet ของ Freeverb
    }
}
