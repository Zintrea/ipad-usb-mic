import Accelerate
import Foundation

/// ค่าที่ปรับได้ขณะทำงาน แยกออกมาเป็น object เดียวที่ไม่ถูกสร้างใหม่ เพื่อไม่ให้ main แก้ reference ชนกับเธรดเสียง
/// เขียนจาก main อ่านจากเธรดเสียง (ค่าเดี่ยว ไม่ต้องล็อก)
final class NoiseSettings {
    var enabled = false
    var floor: Float = 0.1           // gain ต่ำสุด = ความลึกสูงสุด (20 dB)
    var sensitivity: Float = 2       // บวกกี่เท่าของความแปรปรวนเข้าไปใน profile (จับเสียงแทรกตอนเรียน)
}

/// ตัดเสียงรบกวนแบบเรียนเสียงรอบข้าง (spectral subtraction) จำกัดความลึกไม่ให้ลบจนเงียบ
/// FFT ขนาด `size` hop = size/2 หน้าต่าง sqrt-Hann ทั้งขาเข้าและขาออก (รวมกันได้ 1 พอดี)
/// ดีเลย์เท่ากับ `size` sample เมื่อเปิดใช้ FFT ใหญ่แยกเสียงหึ่งออกจากโอเวอร์โทนเสียงร้องได้ละเอียดกว่า
/// เรียนจากค่าเฉลี่ยและความแปรปรวนของแต่ละความถี่ตลอดช่วงเรียน (เสียงขยับ/หายใจที่เข้ามาครั้งคราวจึงถูกตัดด้วย)
/// เรียกจากเธรดเสียงทีละ sample ห้ามจองหน่วยความจำตอนทำงาน
final class NoiseReducer {
    let size: Int
    let hop: Int
    private let settings: NoiseSettings
    var onLearned: (([Float], [Float]) -> Void)?   // (ค่าเฉลี่ย, ส่วนเบี่ยงเบน) เรียกจากเธรดเสียงครั้งเดียวตอนเรียนเสร็จ

    // profile ใช้ pointer ที่จองครั้งเดียวตั้งแต่ init
    private let mean: UnsafeMutablePointer<Float>
    private let dev: UnsafeMutablePointer<Float>
    private(set) var hasProfile = false
    private var learnLeft = 0
    private var learnTotal = 0
    private var learnSum: [Double]
    private var learnSq: [Double]

    private let dftF: vDSP.DFT<Float>?
    private let dftI: vDSP.DFT<Float>?
    private let window: [Float]
    private var inBuf: [Float]
    private var outAcc: [Float]
    private var ready: [Float]
    private var re: [Float]
    private var im: [Float]
    private var zeros: [Float]
    private var outRe: [Float]
    private var outIm: [Float]
    private var smooth: [Float]
    private var count = 0

    init(size: Int, settings: NoiseSettings) {
        self.size = size
        self.hop = size / 2
        self.settings = settings
        mean = .allocate(capacity: size)
        dev = .allocate(capacity: size)
        mean.initialize(repeating: 0, count: size)
        dev.initialize(repeating: 0, count: size)
        learnSum = [Double](repeating: 0, count: size)
        learnSq = [Double](repeating: 0, count: size)
        dftF = vDSP.DFT(count: size, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        dftI = vDSP.DFT(count: size, direction: .inverse, transformType: .complexComplex, ofType: Float.self)
        window = (0..<size).map { Float(sin(Double.pi * Double($0) / Double(size))) }   // sqrt ของ Hann แบบ periodic
        inBuf = [Float](repeating: 0, count: size)
        outAcc = [Float](repeating: 0, count: size)
        ready = [Float](repeating: 0, count: size / 2)
        re = [Float](repeating: 0, count: size)
        im = [Float](repeating: 0, count: size)
        zeros = [Float](repeating: 0, count: size)
        outRe = [Float](repeating: 0, count: size)
        outIm = [Float](repeating: 0, count: size)
        smooth = [Float](repeating: 1, count: size)
    }
    deinit { mean.deallocate(); dev.deallocate() }

    /// ใส่ profile ที่จำไว้ (จาก UserDefaults) ต้องยาว size ตัว
    func setProfile(mean m: [Float], dev d: [Float]) {
        guard m.count == size, d.count == size else { return }
        for i in 0..<size { mean[i] = m[i]; dev[i] = d[i] }
        hasProfile = true
    }

    /// เริ่มเรียน (เรียกจาก main ตอนที่เธรดเสียงไม่ได้แตะ learnSum เพราะ learnLeft = 0)
    func learn(seconds: Double) {
        for i in 0..<size { learnSum[i] = 0; learnSq[i] = 0 }
        learnTotal = max(1, Int(seconds * 48000) / hop)
        learnLeft = learnTotal
    }
    /// เรียกหลัง engine หยุดแล้วเท่านั้น (แตะข้อมูลของเธรดเสียง)
    func cancelLearn() { learnLeft = 0 }

    func process(_ x: Float) -> Float {
        inBuf[size - hop + count] = x
        let y = ready[count]
        count += 1
        if count == hop { count = 0; frame() }
        // ปิดอยู่ = ส่งเสียงตรงไม่มีดีเลย์ (ยังวิเคราะห์ต่อเพื่อให้กดเรียนเสียงได้ตลอด)
        // shortcut: สลับเปิด/ปิดระหว่างร้องจะมีคลิกเบา ๆ 1 ครั้งเพราะดีเลย์เปลี่ยน
        return settings.enabled && hasProfile ? y : x
    }

    private func frame() {
        let n = size, h = hop
        guard let dftF = dftF, let dftI = dftI else { return }
        for i in 0..<n { re[i] = inBuf[i] * window[i] }
        dftF.transform(inputReal: re, inputImaginary: zeros, outputReal: &outRe, outputImaginary: &outIm)

        if learnLeft > 0 {
            for k in 0..<n {
                let m = Double((outRe[k] * outRe[k] + outIm[k] * outIm[k]).squareRoot())
                learnSum[k] += m
                learnSq[k] += m * m
            }
            learnLeft -= 1
            if learnLeft == 0 {
                let frames = Double(learnTotal)
                for k in 0..<n {
                    let mu = learnSum[k] / frames
                    mean[k] = Float(mu)
                    dev[k] = Float(max(0, learnSq[k] / frames - mu * mu).squareRoot())
                }
                hasProfile = true
                // จองครั้งเดียวตอนเรียนเสร็จ
                onLearned?(Array(UnsafeBufferPointer(start: mean, count: n)),
                           Array(UnsafeBufferPointer(start: dev, count: n)))
            }
        }

        let fl = settings.floor, sens = settings.sensitivity
        for k in 0..<n {
            let mag = (outRe[k] * outRe[k] + outIm[k] * outIm[k]).squareRoot()
            // ลบ 2 เท่าของ (ค่าเฉลี่ย + ความแปรปรวน × ความไว) เพราะเสียงรบกวนจริงแกว่งเกินค่าเฉลี่ย
            let prof = mean[k] + sens * dev[k]
            let g = max(fl, mag > 0 ? 1 - 2 * prof / mag : fl)
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
