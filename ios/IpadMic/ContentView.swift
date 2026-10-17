import SwiftUI

struct ContentView: View {
    @ObservedObject var server: MicServer
    @AppStorage("rawMode") private var raw = false   // จำค่าข้ามการเปิดแอป
    @AppStorage("gainDB") private var gainDB = 0.0
    @AppStorage("muted") private var muted = false
    @AppStorage("limiterOn") private var limiterOn = true
    @AppStorage("ceilingDB") private var ceilingDB = -1.0
    @State private var showSettings = false

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
        case .waiting: return muted ? "รอคอมต่อ... (ปิดไมค์)" : "รอคอมต่อ..."
        case .streaming: return muted ? "ปิดไมค์ (ส่งเสียงเงียบ)" : "กำลังส่งเสียง"
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
    // แดงเมื่อใกล้เพดาน หรือค้าง 2 วินาทีหลังเสียงเกิน 0 dBFS ก่อนเข้า limiter
    private var levelColor: Color { server.level >= 0.708 || server.clipping ? .red : .green }

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Color.clear.frame(width: 44, height: 44)
                Spacer()
                Text("iPad Mic")
                    .font(.largeTitle.bold())
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title2).frame(width: 44, height: 44)
                }
            }
            .frame(maxWidth: 360)

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

            VStack(spacing: 8) {
                Text(String(format: "ความดัง %+.0f dB", gainDB))
                Slider(value: $gainDB, in: -24...12, step: 1)
            }
            .frame(maxWidth: 360)

            Button {
                muted.toggle()
            } label: {
                Label(muted ? "เปิดไมค์" : "ปิดไมค์", systemImage: muted ? "mic.slash.fill" : "mic.fill")
                    .font(.title2)
                    .frame(maxWidth: 360, minHeight: 56)
            }
            .buttonStyle(.bordered)
            .tint(muted ? .orange : .green)

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
        .sheet(isPresented: $showSettings) { SettingsView(running: running) }
        .onAppear {
            server.setGain(db: gainDB); server.setMuted(muted)
            server.setLimiter(on: limiterOn, ceilingDB: ceilingDB)
        }
        .onChange(of: gainDB) { server.setGain(db: gainDB) }
        .onChange(of: muted) { server.setMuted(muted) }
        .onChange(of: limiterOn) { server.setLimiter(on: limiterOn, ceilingDB: ceilingDB) }
        .onChange(of: ceilingDB) { server.setLimiter(on: limiterOn, ceilingDB: ceilingDB) }
    }
}
