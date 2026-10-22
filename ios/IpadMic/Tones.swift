import Foundation

/// ค่าเสียงที่ต่างกันตามแหล่งเสียง ค่าเริ่มต้นจาก docs/AUDIO_RESEARCH.md ข้อ 7 (ส่วนใหญ่เป็น [I] ต้องฟังจริงยืนยัน)
struct Tone: Codable, Equatable {
    var lowCutHz: Double
    var mudDB: Double            // ลดอู้ที่ 300 Hz (0 = ไม่ลด)
    var presenceHz: Double
    var presenceDB: Double       // ติดลบได้ ใช้ลดเสียงแหลมแสบของซอ
    var highCutHz: Double        // 20000 = ปิด
    var compOn: Bool
    var compThresholdDB: Double
    var compRatio: Double
    var compAttackMs: Double
    var compReleaseMs: Double
    var noiseDepthDB: Double     // เครื่องสายใช้ตื้นกว่า กันหางเสียงเพี้ยน (ข้อ 4.3)
    var reverbPreset: Int        // 0 ไม่ก้อง 1 ห้อง 2 ฮอลล์
    var reverbMix: Double
    var preDelayMs: Double
    var limiterReleaseMs: Double // เสียงลากยาวใช้ช้ากว่า เสียงจะไม่ย้วย (ข้อ 3.2)
}

enum Source {
    static let names = ["เสียงพูด", "ร้อง + กีตาร์", "ไวโอลิน", "ซอด้วง"]
    static let defaults: [Tone] = [
        Tone(lowCutHz: 100, mudDB: -2, presenceHz: 4000, presenceDB: 2, highCutHz: 20000,
             compOn: true, compThresholdDB: -20, compRatio: 3, compAttackMs: 5, compReleaseMs: 100,
             noiseDepthDB: 20, reverbPreset: 0, reverbMix: 0.1, preDelayMs: 50, limiterReleaseMs: 100),
        Tone(lowCutHz: 75, mudDB: -2, presenceHz: 3000, presenceDB: 1.5, highCutHz: 20000,
             compOn: true, compThresholdDB: -20, compRatio: 2.5, compAttackMs: 15, compReleaseMs: 120,
             noiseDepthDB: 12, reverbPreset: 1, reverbMix: 0.15, preDelayMs: 50, limiterReleaseMs: 100),
        Tone(lowCutHz: 160, mudDB: 0, presenceHz: 3000, presenceDB: 0, highCutHz: 8000,
             compOn: true, compThresholdDB: -20, compRatio: 2, compAttackMs: 40, compReleaseMs: 200,
             noiseDepthDB: 8, reverbPreset: 2, reverbMix: 0.2, preDelayMs: 30, limiterReleaseMs: 250),
        // ซอด้วงฟังคล้ายไวโอลินมากกว่าซอเอ้อหู (ผู้ใช้ยืนยัน) จึงยึดไวโอลิน ตัดต่ำสูงกว่าเพราะเสียงสูงกว่า
        Tone(lowCutHz: 220, mudDB: 0, presenceHz: 3000, presenceDB: 0, highCutHz: 7000,
             compOn: true, compThresholdDB: -20, compRatio: 2, compAttackMs: 40, compReleaseMs: 200,
             noiseDepthDB: 8, reverbPreset: 2, reverbMix: 0.2, preDelayMs: 30, limiterReleaseMs: 250),
    ]
}

/// แหล่งเสียงที่เลือก + ค่าที่แต่งไว้ของทุกแหล่ง จำใน UserDefaults (แต่ละแหล่งจำค่าของตัวเอง)
final class Tones: ObservableObject {
    @Published var source: Int { didSet { UserDefaults.standard.set(source, forKey: "source") } }
    @Published var all: [Tone] { didSet { save() } }

    var current: Tone {
        get { all[source] }
        set { all[source] = newValue }
    }

    init() {
        let s = UserDefaults.standard.integer(forKey: "source")
        source = Source.names.indices.contains(s) ? s : 0
        // ถอดรหัสไม่ได้ (เช่นเพิ่มช่องใหม่ใน Tone) = กลับไปค่าเริ่มต้น
        if let d = UserDefaults.standard.data(forKey: "tones"),
           let t = try? JSONDecoder().decode([Tone].self, from: d), t.count == Source.defaults.count {
            all = t
        } else {
            all = Source.defaults
        }
    }

    func resetCurrent() { all[source] = Source.defaults[source] }

    private func save() {
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: "tones") }
    }
}
