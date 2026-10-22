import SwiftUI

/// ค่าเบื้องหลังทั้งหมดอยู่ที่นี่ ทุกค่ามีคำอธิบายว่าปรับเพื่ออะไร (กฎใน SPEC)
/// ค่าในหมวดตัดเสียงรบกวน (ความแรง) EQ Compressor เสียงก้อง และ release ของ Limiter จำแยกตามแหล่งเสียง
struct SettingsView: View {
    @ObservedObject var server: MicServer
    @ObservedObject var tones: Tones
    let running: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("micMode") private var micMode = 0
    @AppStorage("limiterOn") private var limiterOn = true
    @AppStorage("ceilingDB") private var ceilingDB = -1.0
    @AppStorage("eqOn") private var eqOn = true
    @AppStorage("noiseOn") private var noiseOn = true
    @AppStorage("noiseFFT") private var noiseFFT = 4096
    @AppStorage("noiseLearnSec") private var noiseLearnSec = 30.0
    @AppStorage("noiseSens") private var noiseSens = 2.0

    private var name: String { Source.names[tones.source] }

    private var fftHelp: String {
        switch noiseFFT {
        case 1024: return "1024: ดีเลย์เพิ่ม 21 ms เหมาะกับการเปิดฟังเสียงตัวเองที่คอมแบบสาย แต่แยกเสียงหึ่งออกจากเสียงร้องได้หยาบกว่า เสียงร้องอาจเบาลงเล็กน้อย"
        case 16384: return "16384: ดีเลย์เพิ่ม 341 ms ละเอียดที่สุด เหมาะกับอัดเสียงที่ไม่ต้องคุยโต้ตอบ ไม่เหมาะกับคุยหรือร้องสดใน Discord และอัดวิดีโอต้องชดเชยเวลาใน OBS"
        default: return "4096: ดีเลย์เพิ่ม 85 ms แนะนำสำหรับร้องสดใน Discord และอัดคลิป เหมือน ReaFIR 4096 ที่คุ้นเคย ฟังเสียงตัวเองที่คอมจะช้าตามไปด้วย"
        }
    }

    private var learnStatus: String {
        if micMode == 2 { return "โหมด Apple ตัดเสียงรบกวนให้แล้ว ตัวนี้จึงปิดไว้" }
        if server.noiseLearning { return "กำลังเรียน: ไม่พูดไม่ร้อง ขยับตัว/หายใจ/ลากเก้าอี้ได้ตามปกติ" }
        if !running { return "กด START ที่หน้าหลักก่อนจึงเรียนเสียงได้" }
        return server.hasNoiseProfile ? "เรียนแล้ว กดอีกครั้งถ้าย้ายห้องหรือเปิดแอร์/พัดลมเพิ่ม" : "ยังไม่ได้เรียน กดตอนห้องเงียบตามปกติ"
    }

    /// สไลเดอร์หนึ่งแถว: ชื่อพร้อมค่า สไลเดอร์ และคำอธิบาย
    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double, help: String, off: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Slider(value: value, in: range, step: step).disabled(off)
            Text(help).font(.footnote).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("แหล่งเสียง", selection: $tones.source) {
                        ForEach(Source.names.indices, id: \.self) { Text(Source.names[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("คืนค่าเริ่มต้นของ\(name)") { tones.resetCurrent() }
                } header: {
                    Text("แหล่งเสียง")
                } footer: {
                    Text("เลือกสิ่งที่กำลังอัด แอปจะตั้ง EQ, Compressor, เสียงก้อง และความแรงการตัดเสียงรบกวนให้เหมาะ ค่าที่แต่งเองในหมวดเหล่านี้จำแยกตามแหล่ง สลับไปมาได้ไม่หาย")
                }

                Section {
                    Toggle("เปิดตัดเสียงรบกวน", isOn: $noiseOn)
                        .disabled(micMode == 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Button(String(format: "เรียนเสียงรอบข้าง %.0f วินาที", noiseLearnSec)) {
                            server.learnNoise(seconds: noiseLearnSec)
                        }
                        .disabled(!running || server.noiseLearning || micMode == 2)
                        Text(learnStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    slider(String(format: "ความแรง %.0f dB (%@)", tones.current.noiseDepthDB, name),
                           $tones.current.noiseDepthDB, 0...30, step: 1,
                           help: "ลดเสียงพัดลม/แอร์ที่เรียนไว้ลงได้มากสุดเท่านี้ ยิ่งมากยิ่งเงียบ แต่ถ้ามากไปเสียงร้องและหางเสียงซอจะเพี้ยน เครื่องสายจึงตั้งไว้ต่ำกว่าเสียงพูด",
                           off: !noiseOn || micMode == 2)
                    slider(String(format: "ไวต่อเสียงแทรก %.1f", noiseSens), $noiseSens, 0...3, step: 0.5,
                           help: "ยิ่งมากยิ่งตัดเสียงที่โผล่มาเป็นครั้งคราวตอนเรียน (หายใจ ลากเก้าอี้) ได้มากขึ้น แต่ถ้ามากไปเสียงร้องบางย่านจะเบาลง ค่าเริ่มต้น 2",
                           off: !noiseOn || micMode == 2)
                    slider(String(format: "เวลาเรียนเสียง %.0f วินาที", noiseLearnSec), $noiseLearnSec, 3...60, step: 1,
                           help: "ยิ่งนานยิ่งจับเสียงรอบข้างได้ครบ ค่าเริ่มต้น 30 วินาที")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ความละเอียด (FFT)")
                        Picker("ความละเอียด", selection: $noiseFFT) {
                            Text("1024").tag(1024)
                            Text("4096").tag(4096)
                            Text("16384").tag(16384)
                        }
                        .pickerStyle(.segmented)
                        .disabled(running)
                        Text(fftHelp + " เปลี่ยนได้ตอนหยุดอยู่เท่านั้น และต้องเรียนเสียงใหม่หนึ่งครั้งต่อความละเอียดที่เลือก")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("ตัดเสียงรบกวน")
                }

                Section {
                    Toggle("เปิด EQ", isOn: $eqOn)
                    slider(String(format: "ตัดเสียงต่ำกว่า %.0f Hz", tones.current.lowCutHz),
                           $tones.current.lowCutHz, 60...300, step: 5,
                           help: "ตัดเสียงหึ่ง แอร์ รถ และเสียงกระแทกโต๊ะ พูด 100, ร้อง+กีตาร์ 75 (เก็บสาย E ต่ำของกีตาร์), ไวโอลิน 160, ซอด้วง 220",
                           off: !eqOn)
                    slider(String(format: "ลดเสียงอู้ %.1f dB", tones.current.mudDB),
                           $tones.current.mudDB, -6...0, step: 0.5,
                           help: "ลดย่าน 300 Hz ที่ทำให้เสียงอู้ทึบในห้องเล็ก ถ้าเสียงบางไปให้ขยับเข้าหา 0",
                           off: !eqOn)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ย่านความใส")
                        Picker("ย่านความใส", selection: $tones.current.presenceHz) {
                            Text("2.5k").tag(2500.0)
                            Text("3k").tag(3000.0)
                            Text("4k").tag(4000.0)
                            Text("5k").tag(5000.0)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!eqOn)
                        Text("3 kHz เหมาะกับเสียงร้อง 4 kHz เหมาะกับเสียงพูด").font(.footnote).foregroundStyle(.secondary)
                    }
                    slider(String(format: "ความใส %+.1f dB", tones.current.presenceDB),
                           $tones.current.presenceDB, -4...6, step: 0.5,
                           help: "บวกให้เสียงชัดลอยขึ้นมา ลบเมื่อเสียงแหลมแสบหู ไวโอลินและซอด้วงสว่างอยู่แล้วจึงตั้งไว้ 0 ถ้าซอบาดหูลอง -2 dB ที่ 3k",
                           off: !eqOn)
                    slider(tones.current.highCutHz >= 20000 ? "ตัดเสียงแหลมสูง: ปิด"
                               : String(format: "ตัดเสียงสูงกว่า %.1f kHz", tones.current.highCutHz / 1000),
                           $tones.current.highCutHz, 5000...20000, step: 500,
                           help: "ลดเสียงสีคันชัก/ยางสนที่คันหู เลื่อนขวาสุดเพื่อปิด เสียงพูดและร้องปิดไว้",
                           off: !eqOn)
                } header: {
                    Text("EQ (\(name))")
                }

                Section {
                    Toggle("เปิด Compressor", isOn: $tones.current.compOn)
                    slider(String(format: "เริ่มทำงานที่ %.0f dB", tones.current.compThresholdDB),
                           $tones.current.compThresholdDB, -40...0, step: 1,
                           help: "เสียงที่ดังกว่าค่านี้จะถูกเกลี่ยลง ถ้าแทบไม่ได้ยินผลให้ลดค่าลง ถ้าเสียงแบนไม่มีชีวิตให้เพิ่มค่า",
                           off: !tones.current.compOn)
                    slider(String(format: "อัตราเกลี่ย %.1f:1", tones.current.compRatio),
                           $tones.current.compRatio, 1.5...6, step: 0.5,
                           help: "ยิ่งมากเสียงดัง-เบายิ่งใกล้กัน พูด 3:1 ร้อง 2.5:1 ซอ 2:1",
                           off: !tones.current.compOn)
                    slider(String(format: "เริ่มจับ (attack) %.0f ms", tones.current.compAttackMs),
                           $tones.current.compAttackMs, 1...60, step: 1,
                           help: "ช้าลงจะปล่อยหัวเสียงดีดกีตาร์และการเปลี่ยนคันชักผ่านไปเป็นธรรมชาติ",
                           off: !tones.current.compOn)
                    slider(String(format: "ปล่อย (release) %.0f ms", tones.current.compReleaseMs),
                           $tones.current.compReleaseMs, 50...400, step: 10,
                           help: "เร็วไปเสียงจะวูบวาบ ช้าไปเสียงเบาค้าง",
                           off: !tones.current.compOn)
                } header: {
                    Text("Compressor (\(name))")
                } footer: {
                    Text("เกลี่ยเสียงดังเบาให้สม่ำเสมอ แล้วยกระดับรวมคืนให้อัตโนมัติ")
                }

                Section {
                    Picker("แบบเสียงก้อง", selection: $tones.current.reverbPreset) {
                        Text("ไม่ก้อง").tag(0)
                        Text("ห้อง").tag(1)
                        Text("ฮอลล์").tag(2)
                    }
                    .pickerStyle(.segmented)
                    slider(String(format: "ปริมาณ %.0f%%", tones.current.reverbMix * 100),
                           $tones.current.reverbMix, 0...0.5, step: 0.05,
                           help: "มากไปเสียงจะจมและฟังคำไม่ชัด",
                           off: tones.current.reverbPreset == 0)
                    slider(String(format: "หน่วงก่อนก้อง %.0f ms", tones.current.preDelayMs),
                           $tones.current.preDelayMs, 0...100, step: 5,
                           help: "ให้เสียงก้องตามมาทีหลังเล็กน้อย คำร้องจึงยังชัด ร้อง 50 ms ซอ 30 ms",
                           off: tones.current.reverbPreset == 0)
                } header: {
                    Text("เสียงก้อง (\(name))")
                }

                Section {
                    Toggle("เปิด Limiter", isOn: $limiterOn)
                    slider(String(format: "เพดานเสียง %.1f dB", ceilingDB), $ceilingDB, -6...(-0.5), step: 0.5,
                           help: "ระดับสูงสุดที่เสียงจะไปถึง ยิ่งต่ำยิ่งเหลือที่ว่างกันเสียงแตก แต่เสียงรวมเบาลง ค่าเริ่มต้น -1 dB",
                           off: !limiterOn)
                    slider(String(format: "คืนระดับใน %.0f ms (%@)", tones.current.limiterReleaseMs, name),
                           $tones.current.limiterReleaseMs, 50...400, step: 10,
                           help: "เสียงลากยาวอย่างซอใช้ค่ามากกว่า เสียงจะไม่ย้วยตอนโดนหรี่",
                           off: !limiterOn)
                } header: {
                    Text("Limiter")
                } footer: {
                    Text("กันเสียงแตกเมื่อร้องหรือดีดแรงเกินไป ตอนร้องปกติไม่ทำอะไร ถ้าแถบระดับเสียงแดงบ่อยให้ลดความดังที่หน้าหลักแทน แนะนำให้เปิดไว้")
                }

                Section {
                    Picker("โหมดเสียง", selection: $micMode) {
                        Text("มาตรฐาน").tag(0)
                        Text("ดิบ").tag(1)
                        Text("Apple").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .disabled(running)
                } header: {
                    Text("โหมดไมค์")
                } footer: {
                    Text("มาตรฐาน: iPad ปรับความดังและแต่งเสียงให้เอง เสียงเต็มและดังกว่า (แนะนำ) ดิบ: ไม่แต่งเสียงเลย แต่เบาและทึบ ใช้เทียบเสียงเท่านั้น Apple: ใช้ตัวตัดเสียงรบกวนของ Apple แทนของแอป (ทำมาเพื่อเสียงพูด เสียงร้องและซอลากยาวอาจเบาลง) เปลี่ยนได้ตอนหยุดอยู่เท่านั้น")
                }

                Section {
                    Button("คืนค่าเริ่มต้นทั้งหมด", role: .destructive) {
                        limiterOn = true
                        ceilingDB = -1.0
                        eqOn = true
                        noiseOn = true
                        noiseLearnSec = 30
                        noiseSens = 2
                        tones.all = Source.defaults
                        if !running { noiseFFT = 4096 }
                        if !running { micMode = 0 }
                    }
                } footer: {
                    Text("คืนค่าทุกแหล่งเสียงและทุกหมวด เสียงรอบข้างที่เรียนไว้ไม่หาย")
                }
            }
            .navigationTitle("ตั้งค่า")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ") { dismiss() }
                }
            }
        }
    }
}
