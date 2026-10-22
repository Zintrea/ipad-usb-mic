import SwiftUI

struct ContentView: View {
    @ObservedObject var server: MicServer
    @AppStorage("micMode") private var micMode = 0   // จำค่าข้ามการเปิดแอป
    @AppStorage("gainDB") private var gainDB = 0.0
    @AppStorage("muted") private var muted = false
    @AppStorage("limiterOn") private var limiterOn = true
    @AppStorage("ceilingDB") private var ceilingDB = -1.0
    @AppStorage("eqOn") private var eqOn = true
    @AppStorage("lowCutHz") private var lowCutHz = 100.0
    @AppStorage("presenceDB") private var presenceDB = 3.0
    @AppStorage("reverbPreset") private var reverbPreset = 0
    @AppStorage("reverbMix") private var reverbMix = 0.2
    @AppStorage("noiseOn") private var noiseOn = true
    @AppStorage("noiseDepthDB") private var noiseDepthDB = 20.0
    @AppStorage("noiseFFT") private var noiseFFT = 4096
    @AppStorage("noiseLearnSec") private var noiseLearnSec = 30.0
    @AppStorage("noiseSens") private var noiseSens = 2.0
    @State private var showSettings = false
    @State private var monitor = false   // ไม่จำค่า: เปิดแอปใหม่ปิดเสมอ กันเสียงหอนถ้าลืมถอดหูฟังแล้วเปิดลำโพง

    private var noiseHint: String {
        if micMode == 2 { return "โหมด Apple ตัดเสียงรบกวนให้แล้ว ตัวนี้จึงปิดไว้ (เปลี่ยนโหมดในตั้งค่า)" }
        if server.noiseLearning {
            return String(format: "กำลังเรียนเสียงรอบข้าง %.0f วินาที: ไม่พูดไม่ร้อง ขยับตัว/หายใจ/ลากเก้าอี้ได้ตามปกติ", noiseLearnSec)
        }
        if !server.hasNoiseProfile { return "ยังไม่ได้เรียนเสียง: กด START แล้วกดเรียนเสียงตอนเงียบ" }
        return running ? " " : "กด START ก่อนจึงเรียนเสียงใหม่ได้"
    }

    // ส่งค่าเสียงทั้งหมดให้ server (ค่าถูกจำใน AppStorage ทั้งหน้านี้และหน้าตั้งค่า)
    private func applyAudio() {
        server.setGain(db: gainDB); server.setMuted(muted)
        server.setLimiter(on: limiterOn, ceilingDB: ceilingDB)
        server.setEQ(on: eqOn, lowCutHz: lowCutHz, presenceDB: presenceDB)
        server.setReverb(preset: reverbPreset, mix: reverbMix)
        server.setNoise(on: noiseOn && micMode != 2,   // โหมด Apple ตัดเสียงให้แล้ว ตัดซ้ำจะทึบ
                         depthDB: noiseDepthDB, sensitivity: noiseSens)
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

            Picker("เสียงก้อง", selection: $reverbPreset) {
                Text("ไม่ก้อง").tag(0)
                Text("ห้อง").tag(1)
                Text("ฮอลล์").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            VStack(spacing: 8) {
                HStack {
                    Toggle("ตัดเสียงรบกวน", isOn: $noiseOn)
                        .disabled(micMode == 2)
                    Button("เรียนเสียงรอบข้าง") { server.learnNoise(seconds: noiseLearnSec) }
                        .buttonStyle(.bordered)
                        .disabled(!running || server.noiseLearning || micMode == 2)
                }
                Text(noiseHint).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360)

            Toggle("ฟังเสียงตัวเองที่คอม (หูฟังเท่านั้น)", isOn: $monitor)
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

            Text(running ? String(format: "ก้อนละ %.1f ms", server.chunkMs) : " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .sheet(isPresented: $showSettings) { SettingsView(running: running) }
        .onAppear { applyAudio() }
        .onChange(of: gainDB) { applyAudio() }
        .onChange(of: muted) { applyAudio() }
        .onChange(of: limiterOn) { applyAudio() }
        .onChange(of: ceilingDB) { applyAudio() }
        .onChange(of: eqOn) { applyAudio() }
        .onChange(of: lowCutHz) { applyAudio() }
        .onChange(of: presenceDB) { applyAudio() }
        .onChange(of: reverbPreset) { applyAudio() }
        .onChange(of: reverbMix) { applyAudio() }
        .onChange(of: noiseOn) { applyAudio() }
        .onChange(of: micMode) { applyAudio() }
        .onChange(of: noiseDepthDB) { applyAudio() }
        .onChange(of: noiseSens) { applyAudio() }
        .onChange(of: monitor) { applyAudio() }
    }
}
