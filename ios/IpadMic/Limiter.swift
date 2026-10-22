import Foundation

/// Limiter แบบมอง 1 ms ล่วงหน้า: หรี่เสียงลงก่อนที่ peak จะมาถึงเพดาน แล้วค่อยคืนระดับตาม releaseMs (ค่าเริ่มต้น 100 ms)
/// ดีเลย์คงที่ 1 ms ตลอด (แม้ปิดอยู่) เพื่อไม่ให้เกิดเสียงคลิกตอนสลับเปิด/ปิด
/// ไม่ผูกกับ AVFoundation และไม่จองหน่วยความจำตอนทำงาน เรียกจากเธรดเสียงได้
final class Limiter {
    static let lookahead = 48            // 1 ms ที่ 48 kHz

    // เขียนจาก main อ่านจากเธรดเสียง (ค่าเดียว ไม่ต้องล็อก)
    var enabled = true
    var ceiling: Float = 0.891           // -1 dBFS

    private var delay = [Float](repeating: 0, count: Limiter.lookahead)
    private var need = [Float](repeating: 1, count: Limiter.lookahead)   // gain ที่แต่ละ sample ต้องการ
    private var pos = 0
    private var gain: Float = 1
    // shortcut: attack แบบ exponential ไม่การันตีว่าถึงเพดานพอดีใน 1 ms (เหลือเกินไม่ถึง 1%)
    // ส่วนที่เกินถูกดูดซับด้วยช่องว่างระหว่างเพดานกับ ±1 ที่ MicServer ตัดซ้ำ; ถ้าต้องเป๊ะให้ใช้ ramp เชิงเส้น
    private let attack: Float = 0.1
    private var release: Float = 1 - exp(-1 / (0.1 * 48000))
    func setRelease(ms: Double) { release = Float(1 - exp(-1 / (ms / 1000 * 48000))) }

    func process(_ x: Float) -> Float {
        let a = abs(x)
        let c = ceiling
        let out = delay[pos]
        var target = need[pos]           // sample ที่กำลังออกต้องรวมในช่วงที่หรี่ด้วย
        need[pos] = (enabled && a > c) ? c / a : 1
        delay[pos] = x
        pos += 1
        if pos == Limiter.lookahead { pos = 0 }
        for v in need { target = min(target, v) }
        gain += (target - gain) * (target < gain ? attack : release)
        return out * gain
    }
}
