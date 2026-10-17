import SwiftUI

struct ContentView: View {
    @ObservedObject var server: MicServer
    @AppStorage("rawMode") private var raw = false   // จำค่าข้ามการเปิดแอป

    // ใช้สีของระบบทั้งหมด เพื่อให้โหมดมืด/สว่างทำงานเอง
    private var dotColor: Color {
        switch server.state {
        case .stopped: return .gray
        case .waiting: return .yellow
        case .streaming: return .green
        case .interrupted: return .orange
        case .error: return .red
        }
    }

    private var statusText: String {
        switch server.state {
        case .stopped: return "หยุดอยู่"
        case .waiting: return "รอคอมต่อ..."
        case .streaming: return "กำลังส่งเสียง"
        case .interrupted: return "Interrupted – กด Start ใหม่"
        case .error(let message): return message
        }
    }

    private var running: Bool {
        server.state == .waiting || server.state == .streaming
    }

    // peak 0...1 แสดงเป็น dB (-60...0) แถบจะขยับเห็นชัดกว่าสเกลเส้นตรง; แดงเมื่อ >= -3 dBFS
    private var levelFraction: CGFloat {
        guard server.level > 0 else { return 0 }
        return CGFloat(max(0, min(1, (20 * log10(server.level) + 60) / 60)))
    }
    private var levelColor: Color { server.level >= 0.708 ? .red : .green }

    var body: some View {
        VStack(spacing: 32) {
            Text("iPad Mic")
                .font(.largeTitle.bold())

            HStack(spacing: 12) {
                Circle().fill(dotColor).frame(width: 20, height: 20)
                Text(statusText).font(.title2)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(levelColor)
                        .frame(width: geo.size.width * levelFraction)
                }
            }
            .frame(maxWidth: 360, minHeight: 24, maxHeight: 24)

            // เปลี่ยนโหมดได้ตอนหยุดเท่านั้น เพราะต้องตั้ง AVAudioSession ใหม่
            Picker("โหมดเสียง", selection: $raw) {
                Text("มาตรฐาน (แนะนำ)").tag(false)
                Text("ดิบ").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .disabled(running)

            Button {
                if running { server.stop() } else { server.start(raw: raw) }
            } label: {
                Text(running ? "STOP" : "START")
                    .font(.system(size: 36, weight: .bold))
                    .frame(maxWidth: 360, minHeight: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(running ? .red : .blue)

            Text(running ? String(format: "ก้อนละ %.1f ms", server.chunkMs) : " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
