import SwiftUI

/// ค่าเบื้องหลังทั้งหมดอยู่ที่นี่ ทุกค่ามีคำอธิบายว่าปรับเพื่ออะไร (กฎใน SPEC)
struct SettingsView: View {
    let running: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rawMode") private var raw = false
    @AppStorage("limiterOn") private var limiterOn = true
    @AppStorage("ceilingDB") private var ceilingDB = -1.0
    @AppStorage("eqOn") private var eqOn = true
    @AppStorage("lowCutHz") private var lowCutHz = 100.0
    @AppStorage("presenceDB") private var presenceDB = 3.0
    @AppStorage("reverbMix") private var reverbMix = 0.2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("เปิด Limiter", isOn: $limiterOn)
                } footer: {
                    Text("กันเสียงแตกเมื่อร้องหรือดีดแรงเกินไป จะหรี่เสียงลงชั่วขณะเฉพาะตอนที่ดังเกินเพดาน ตอนร้องปกติไม่ทำอะไร แนะนำให้เปิดไว้")
                }
                Section {
                    Slider(value: $ceilingDB, in: -6...(-0.5), step: 0.5)
                        .disabled(!limiterOn)
                } header: {
                    Text(String(format: "เพดานเสียง %.1f dB", ceilingDB))
                } footer: {
                    Text("ระดับสูงสุดที่เสียงจะไปถึง ยิ่งต่ำยิ่งเหลือที่ว่างกันเสียงแตก แต่เสียงรวมเบาลง ค่าเริ่มต้น -1 dB")
                }
                Section {
                    Toggle("เปิด EQ เสียงร้อง", isOn: $eqOn)
                } footer: {
                    Text("แต่งเสียงให้ใสและสะอาดขึ้น: ตัดเสียงต่ำที่ไม่ต้องการ (เสียงหึ่ง ลมหายใจกระแทก) และเพิ่มความชัดของเสียงร้อง")
                }
                Section {
                    Slider(value: $lowCutHz, in: 60...200, step: 10)
                        .disabled(!eqOn)
                } header: {
                    Text(String(format: "ตัดเสียงต่ำกว่า %.0f Hz", lowCutHz))
                } footer: {
                    Text("ตัดเสียงทุ้มที่ต่ำกว่าค่านี้ ช่วยลดเสียงหึ่งของแอร์/รถ ถ้าเสียงกีตาร์บางเกินไปให้ลดค่าลง ค่าเริ่มต้น 100 Hz")
                }
                Section {
                    Slider(value: $presenceDB, in: 0...6, step: 0.5)
                        .disabled(!eqOn)
                } header: {
                    Text(String(format: "เพิ่มความใส +%.1f dB", presenceDB))
                } footer: {
                    Text("เพิ่มย่านเสียงประมาณ 4 kHz ให้เสียงร้องชัดและลอยขึ้นมา ถ้าเสียงแหลมบาดหูให้ลดค่าลง ค่าเริ่มต้น +3 dB")
                }
                Section {
                    Slider(value: $reverbMix, in: 0...0.5, step: 0.05)
                } header: {
                    Text(String(format: "ปริมาณเสียงก้อง %.0f%%", reverbMix * 100))
                } footer: {
                    Text("ผสมเสียงก้องมากน้อยแค่ไหน (เลือกแบบห้อง/ฮอลล์ที่หน้าหลัก) มากไปเสียงจะจมและฟังคำไม่ชัด ค่าเริ่มต้น 20%")
                }
                Section {
                    Picker("โหมดเสียง", selection: $raw) {
                        Text("มาตรฐาน").tag(false)
                        Text("ดิบ").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(running)
                } footer: {
                    Text("มาตรฐาน: iPad ปรับความดังและแต่งเสียงให้เอง เสียงเต็มและดังกว่า (แนะนำ) ดิบ: ไม่แต่งเสียงเลย แต่เบาและทึบ ใช้เทียบเสียงเท่านั้น เปลี่ยนได้ตอนหยุดอยู่เท่านั้น")
                }
                Section {
                    Button("คืนค่าเริ่มต้น", role: .destructive) {
                        limiterOn = true
                        ceilingDB = -1.0
                        eqOn = true
                        lowCutHz = 100
                        presenceDB = 3
                        reverbMix = 0.2
                        if !running { raw = false }
                    }
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
