import SwiftUI

/// ค่าเบื้องหลังทั้งหมดอยู่ที่นี่ ทุกค่ามีคำอธิบายว่าปรับเพื่ออะไร (กฎใน SPEC)
struct SettingsView: View {
    let running: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rawMode") private var raw = false
    @AppStorage("limiterOn") private var limiterOn = true
    @AppStorage("ceilingDB") private var ceilingDB = -1.0

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
