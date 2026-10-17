import Accelerate
import Foundation

/// ตัดเสียงรบกวนแบบเรียนเสียงรอบข้าง (spectral subtraction) จำกัดความลึกไม่ให้ลบจนเงียบ
/// เพื่อไม่กินเสียงซอ/กีตาร์ และไม่เกิดเสียงเพี้ยนแบบเสียงในน้ำ
/// FFT 512 จุด hop 256 หน้าต่าง sqrt-Hann ทั้งขาเข้าและขาออก (รวมกันได้ 1 พอดี) ดีเลย์ 512 sample ≈ 10.7 ms ตอนเปิด
/// เรียกจากเธรดเสียงทีละ sample ห้ามจองหน่วยความจำตอนทำงาน
final class NoiseReducer {
    static let size = 512
    static let hop = 256
    static let learnFrames = 3 * 48000 / hop     // 3 วินาที

    // เขียนจาก main อ่านจากเธรดเสียง (ค่าเดียว ไม่ต้องล็อก)
    var enabled = false
    var floor: Float = 0.316                      // gain ต่ำสุด = ความลึก 10 dB
    var onLearned: (([Float]) -> Void)?           // เรียกจากเธรดเสียงครั้งเดียวตอนเรียนเสร็จ

    // profile ใช้ pointer ที่จองครั้งเดียว: main เขียนทับค่าได้โดยไม่ย้ายหน่วยความจำขณะเธรดเสียงอ่าน
    private let profile = UnsafeMutablePointer<Float>.allocate(capacity: NoiseReducer.size)
    private(set) var hasProfile = false
    private var learnLeft = 0
    private var learnSum = [Float](repeating: 0, count: NoiseReducer.size)

    private let dftF = vDSP.DFT(count: NoiseReducer.size, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private let dftI = vDSP.DFT(count: NoiseReducer.size, direction: .inverse, transformType: .complexComplex, ofType: Float.self)
    private let window: [Float]
    private var inBuf = [Float](repeating: 0, count: NoiseReducer.size)
    private var outAcc = [Float](repeating: 0, count: NoiseReducer.size)
    private var ready = [Float](repeating: 0, count: NoiseReducer.hop)
    private var re = [Float](repeating: 0, count: NoiseReducer.size)
    private var im = [Float](repeating: 0, count: NoiseReducer.size)
    private var zeros = [Float](repeating: 0, count: NoiseReducer.size)
    private var outRe = [Float](repeating: 0, count: NoiseReducer.size)
    private var outIm = [Float](repeating: 0, count: NoiseReducer.size)
    private var smooth = [Float](repeating: 1, count: NoiseReducer.size)
    private var count = 0

    init() {
        let n = NoiseReducer.size
        window = (0..<n).map { Float(sin(Double.pi * Double($0) / Double(n))) }   // sqrt ของ Hann แบบ periodic
        profile.initialize(repeating: 0, count: n)
    }
    deinit { profile.deallocate() }

    /// ใส่ profile ที่จำไว้ (จาก UserDefaults) ต้องยาว size ตัว
    func setProfile(_ p: [Float]) {
        guard p.count == NoiseReducer.size else { return }
        for i in 0..<p.count { profile[i] = p[i] }
        hasProfile = true
    }

    func learn() { learnLeft = NoiseReducer.learnFrames }
    /// เรียกหลัง engine หยุดแล้วเท่านั้น (แตะข้อมูลของเธรดเสียง)
    func cancelLearn() {
        learnLeft = 0
        for i in 0..<learnSum.count { learnSum[i] = 0 }
    }
    var learning: Bool { learnLeft > 0 }

    func process(_ x: Float) -> Float {
        let h = NoiseReducer.hop
        inBuf[NoiseReducer.size - h + count] = x
        let y = ready[count]
        count += 1
        if count == h { count = 0; frame() }
        // ปิดอยู่ = ส่งเสียงตรงไม่มีดีเลย์ (ยังวิเคราะห์ต่อเพื่อให้กดเรียนเสียงได้ตลอด)
        // shortcut: สลับเปิด/ปิดระหว่างร้องจะมีคลิกเบา ๆ 1 ครั้งเพราะดีเลย์เปลี่ยน 10.7 ms
        return enabled && hasProfile ? y : x
    }

    private func frame() {
        let n = NoiseReducer.size, h = NoiseReducer.hop
        guard let dftF = dftF, let dftI = dftI else { return }
        for i in 0..<n { re[i] = inBuf[i] * window[i] }
        dftF.transform(inputReal: re, inputImaginary: zeros, outputReal: &outRe, outputImaginary: &outIm)

        if learnLeft > 0 {
            for k in 0..<n { learnSum[k] += (outRe[k] * outRe[k] + outIm[k] * outIm[k]).squareRoot() }
            learnLeft -= 1
            if learnLeft == 0 {
                let frames = Float(NoiseReducer.learnFrames)
                for k in 0..<n { profile[k] = learnSum[k] / frames; learnSum[k] = 0 }
                hasProfile = true
                onLearned?(Array(UnsafeBufferPointer(start: profile, count: n)))   // จองครั้งเดียวตอนเรียนเสร็จ
            }
        }

        let fl = floor
        for k in 0..<n {
            let mag = (outRe[k] * outRe[k] + outIm[k] * outIm[k]).squareRoot()
            // ลบ 2 เท่าของค่าเฉลี่ยเสียงรบกวน เพราะเสียงรบกวนจริงแกว่งเกินค่าเฉลี่ย
            let g = max(fl, mag > 0 ? 1 - 2 * profile[k] / mag : fl)
            // ขึ้นทันที (ไม่กินหัวโน้ต) ลงช้า (ลดเสียงเพี้ยนแบบเสียงในน้ำ)
            let s = g > smooth[k] ? g : smooth[k] * 0.7 + g * 0.3
            smooth[k] = s
            outRe[k] *= s; outIm[k] *= s
        }
        dftI.transform(inputReal: outRe, inputImaginary: outIm, outputReal: &re, outputImaginary: &im)

        let scale = 1 / Float(n)                   // inverse DFT ของ vDSP ไม่หารด้วย n
        for i in 0..<n { outAcc[i] += re[i] * window[i] * scale }
        for i in 0..<h { ready[i] = outAcc[i] }
        for i in 0..<(n - h) { outAcc[i] = outAcc[i + h]; inBuf[i] = inBuf[i + h] }
        for i in (n - h)..<n { outAcc[i] = 0 }
    }
}
