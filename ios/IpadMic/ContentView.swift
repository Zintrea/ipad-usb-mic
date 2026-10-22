import SwiftUI

struct ContentView: View {
    @ObservedObject var server: MicServer
    @ObservedObject var tones: Tones
    @AppStorage("micMode") private var micMode = 0   // จำค่าข้ามการเปิดแอป
    @AppStorage("gainDB") private var gainDB = 0.0
    @AppStorage("muted") private var muted = false
    @AppStorage("limiterOn") private var limiterOn = true
    @AppStorage("ceilingDB") private var ceilingDB = -1.0
    @AppStorage("eqOn") private var eqOn = true
    @AppStorage("noiseOn") private var noiseOn = true
    @AppStorage("noiseFFT") private var noiseFFT = 4096
    @AppStorage("noiseLearnSec") private var noiseLearnSec = 30.0
    @AppStorage("noiseSens") private var noiseSens = 2.0
    @State private var showSettings = false
    @State private var monitor = false   // ไม่จำค่า: เปิดแอปใหม่ปิดเสมอ กันเสียงหอนถ้าลืมถอดหูฟังแล้วเปิดลำโพง

    private var noiseHint: String {
        if micMode == 2 { return "ตัดเสียงรบกวน: ใช้ของ Apple (เปลี่ยนโหมดในตั้งค่า)" }
        if !noiseOn { return "ตัดเสียงรบกวน: ปิดอยู่ (เปิดในตั้งค่า)" }
        if server.noiseLearning {
            return String(format: "กำลังเรียนเสียงรอบข้าง %.0f วินาที: ไม่พูดไม่ร้อง ขยับตัว/หายใจ/ลากเก้าอี้ได้ตามปกติ", noiseLearnSec)
        }
        if !server.hasNoiseProfile { return "ยังไม่ได้เรียนเสียงรอบข้าง: กด START แล้วไปกดเรียนเสียงในตั้งค่า" }
        return "ตัดเสียงรบกวน: เรียนเสียงรอบข้างแล้ว"
    }

    // ดีเลย์ที่เกิดใน iPad: ก้อนเสียงจากไมค์ + ตัวตัดเสียงรบกวน (เท่าขนาด FFT) + limiter 1 ms
    private var delayText: String {
        guard running else { return " " }
        let nr = noiseOn && micMode != 2 && server.hasNoiseProfile ? Double(noiseFFT) / 48 : 0
        return String(format: "เสียงช้ากว่าจริงประมาณ %.0f มิลลิวินาที (เฉพาะใน iPad ยังไม่รวมสายและคอม)",
                      server.chunkMs + nr + 1)
    }

    // ส่งค่าเสียงทั้งหมดให้ server (ค่าถูกจำใน AppStorage ทั้งหน้านี้และหน้าตั้งค่า)
    private func applyAudio() {
        server.setGain(db: gainDB); server.setMuted(muted)
        server.setLimiter(on: limiterOn, ceilingDB: ceilingDB)
        server.setTone(tones.current, eqOn: eqOn)
        server.setNoise(on: noiseOn && micMode != 2,   // โหมด Apple ตัดเสียงให้แล้ว ตัดซ้ำจะทึบ
                         depthDB: tones.current.noiseDepthDB, sensitivity: noiseSens)
        server.setMonitor(monitor)
    }

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

            Text("แหล่งเสียง: " + Source.names[tones.source])
                .font(.headline)

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

            Text(noiseHint).font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            VStack(spacing: 4) {
                Toggle("ฟังเสียงตัวเองที่คอม (หูฟังเท่านั้น)", isOn: $monitor)
                Text(delayText).font(.footnote).foregroundStyle(.secondary)
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
                if running { server.stop() } else { server.start(mode: micMode, fft: noiseFFT) }
            } label: {
                Text(running ? "STOP" : "START")
                    .font(.system(size: 36, weight: .bold))
                    .frame(maxWidth: 360, minHeight: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(running ? .red : .blue)
        }
        .padding()
        .sheet(isPresented: $showSettings) { SettingsView(server: server, tones: tones, running: running) }
        .onAppear { applyAudio() }
        .onChange(of: gainDB) { applyAudio() }
        .onChange(of: muted) { applyAudio() }
        .onChange(of: limiterOn) { applyAudio() }
        .onChange(of: ceilingDB) { applyAudio() }
        .onChange(of: eqOn) { applyAudio() }
        .onChange(of: tones.source) { applyAudio() }
        .onChange(of: tones.all) { applyAudio() }
        .onChange(of: noiseOn) { applyAudio() }
        .onChange(of: micMode) { applyAudio() }
        .onChange(of: noiseSens) { applyAudio() }
        .onChange(of: monitor) { applyAudio() }
    }
}
