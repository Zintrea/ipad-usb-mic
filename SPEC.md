# Project: iPad-as-USB-Mic (Windows) — สำหรับร้องเพลง

## เป้าหมาย
iPad เป็นไมค์คุณภาพสูงสุดเท่าที่ไมค์ในตัวทำได้ ส่งให้ Windows ผ่าน USB-C
หลักการ: ง่ายที่สุด (เสียบสาย → เปิดแอป → START), เสียงไม่สะดุด, latency ต่ำ
- แอป iPad: Start/Stop + สถานะ + แถบระดับเสียง (ขึ้นสีแดงเมื่อใกล้ clip)
- ต้องอัดต่อได้แม้ล็อกจอ
- ใช้งาน: เสียบสาย → เปิดแอป → Start → เลือก "CABLE Output" ใน DAW

## ข้อเท็จจริงที่สรุปมาแล้ว
(ไม่ต้องค้นซ้ำ ยกเว้นพบว่าขัดกับผลจริงตอนทำ ถ้าขัดให้หยุดและรายงาน)
- iPadOS เป็น USB Audio Class ไม่ได้ → ต้องมีโปรแกรมฝั่ง Windows
- WO Mic iOS = Wi-Fi เท่านั้น / AudioRelay ไม่รองรับ iOS / iVCam = เว็บแคม → สร้างเอง
- Swift Playgrounds เปิด background audio ไม่ได้
- ไม่มี Mac → build ด้วย GitHub Actions แบบไม่เซ็น → ติดตั้งด้วย AltServer + Apple ID ฟรี
  (Sideloadly/iloader ล็อกอิน Apple ไม่ผ่านตั้งแต่ ก.ย. 2026 ดู [GUIDE ข้อ 8](docs/GUIDE.md#8-ทำไมใช้-altserver-ไม่ใช้-sideloadly--iloader))
  (หมดอายุทุก 7 วัน, ลงได้สูงสุด 3 แอป, สร้าง App ID ได้ 10 ตัวต่อ 7 วัน)
- UIBackgroundModes = audio ใช้กับ Apple ID ฟรีได้
- ตรวจแล้วใน spike: AltServer ต้องใช้ iTunes + iCloud เวอร์ชันเว็บ (เวอร์ชัน Microsoft Store ใช้ไม่ได้)

## สถาปัตยกรรม
iPad mic → AVAudioEngine + AVAudioSinkNode (Float32 mono 48 kHz, mode .default ค่าเริ่มต้น / .measurement = โหมดดิบ)
→ TCP listener port 7777 (noDelay, ก้อนละประมาณ 10 ms)
→ usbmux (Apple Devices) → Python + pymobiledevice3
→ jitter buffer 30 ms + ชดเชย drift ด้วย np.interp
→ sounddevice (WASAPI) → "CABLE Input" → DAW เลือก "CABLE Output"

## C1. แอป iPad (`ios/`)
- SwiftUI, iPadOS 17+, ไม่มี dependency, ใช้ XcodeGen (`project.yml`)
- AVAudioSession: .record + .default (ค่าเริ่มต้น มี auto gain) หรือ .measurement (โหมดดิบ เลือกในแอป), preferredSampleRate 48000
  (เดิมบังคับ .measurement แต่ทดสอบจริง 2026-10-17 เสียงเบาและทึบ ดู LOG)
  ถ้าได้ rate อื่นให้แสดง error (ไม่ทำตัวแปลง)
- ส่ง Float32 ตรงจาก inputNode tap แบบ mono
- กด Start แล้ว engine รันตลอดจนกว่าจะกด Stop
  ถ้ายังไม่มี client ให้ทิ้ง sample ไป เพื่อไม่ให้แอปถูก suspend ตอนล็อกจอ
- header ครั้งแรก: magic, version, sample rate, channels, format → ตามด้วย PCM ล้วน
- รับ client ได้ครั้งละ 1 ตัว ถ้า client หลุดให้กลับไปรอ
- เกิด interruption หรือ route change → หยุด แล้วแสดง "Interrupted – กด Start ใหม่"
- สถานะ: Waiting / Streaming / Interrupted
- Info.plist: NSMicrophoneUsageDescription, UIBackgroundModes = [audio]

## C2. ตัวรับ Windows (`windows/`)
- Python 3.11+ ใน `windows/.venv` ใช้ pymobiledevice3, sounddevice, numpy
- หา iPad อัตโนมัติ, ต่อใหม่เองเมื่อถอดสายหรือแอปหยุด
- jitter buffer เริ่มที่ 30 ms (ปรับได้ด้วย `--buffer-ms`)
- ชดเชย drift: ปรับอัตรา resample ทีละน้อยด้วย np.interp
  เพื่อคุมระดับ buffer ให้อยู่ใกล้เป้า (ไม่แทรกหรือตัด sample)
- หา device "CABLE Input" อัตโนมัติ, มี `--device` ให้เลือกเอง
- ใช้ WASAPI ถ้า rate ไม่ตรง 48k ให้แจ้ง error ที่อ่านเข้าใจได้
- log ทุก 10 วินาที: ระดับ buffer, underrun, drift (ppm)
- `start.bat` เปิดหน้าต่าง console ธรรมดา

## C3. CI (`.github/workflows/build.yml`)
- macOS runner → xcodegen → xcodebuild archive
  (-sdk iphoneos, generic/platform=iOS, CODE_SIGNING_ALLOWED=NO)
- แพ็กเป็น .ipa แล้ว upload artifact
- รันเมื่อ push หรือ workflow_dispatch

## C4. เอกสาร (ภาษาไทย)
- README.md = ติดตั้งและใช้งาน มีคำสั่งจริงและผลที่ควรเห็น
  - Apple Devices, VB-Cable (ตั้ง 48 kHz ทั้ง Input และ Output, ปิด Audio enhancements)
  - AltServer (iTunes + iCloud เวอร์ชันเว็บ) → Developer Mode → trust profile → "Trust This Computer"
  - ลงซ้ำทุก 7 วัน
  - คำแนะนำสำหรับร้องเพลง:
    - ห่างไมค์ 20–40 cm และหันขอบ iPad ด้านที่มีไมค์เข้าหาปาก
    - แถบระดับเสียงต้องไม่แดง
    - ปิด noise suppression ใน Discord/Zoom
    - ฟังเสียงตัวเองจากหูฟังแบบตรง ห้ามฟังผ่าน PC
    - ตั้งค่าชดเชย latency ใน DAW
  - แก้ปัญหาที่พบบ่อย
- LOG.md = บันทึกตามวันที่ (การเปลี่ยนแปลง, การตัดสินใจ, ปัญหา) ไม่เขียนซ้ำกับ README

## ลำดับงาน

| เฟส | งาน | หลักฐานว่าผ่าน |
|---|---|---|
| 1 Spike | repo + CI + แอปส่ง sine 440 Hz + receiver เล็กสุด | CI ผ่าน, มี .ipa / log แสดง header / WAV จาก CABLE Output เป็น 440 Hz |
| 2 ไมค์จริง | ไมค์จริง + ล็อกจอ + ต่อใหม่อัตโนมัติ + drift | ล็อกจอ 10 นาทีโดยไม่มี underrun / ทดสอบ 1 ชั่วโมงแล้ว buffer ไม่หลุดเป้า / ถอดแล้วเสียบสายใหม่แล้วกลับมาเอง / WAV เสียงร้อง |
| 3 เอกสาร | README + LOG | ผู้ใช้ทำตาม README ได้จริง |
| 4 ฟีเจอร์เสียง | iPhone, limiter, EQ/reverb, ตัดเสียงรบกวนแบบเรียนเสียง, ฟังเสียงตัวเอง (ลำดับและรายละเอียดใน [next.md](docs/plans/next.md)) | ผู้ใช้ทดสอบ ipa ของแต่ละ branch แล้วผ่านก่อน merge เข้า `dev` |

## กฎ UI ฟีเจอร์เสียง
- หน้าหลักมีเฉพาะที่ใช้บ่อย; ค่าขั้นสูงอยู่หน้าตั้งค่าแยก
- ทุกค่าในหน้าตั้งค่ามีคำอธิบายบรรทัดเดียวว่าปรับเพื่ออะไร และมีปุ่มคืนค่าเริ่มต้น
- ค่าเริ่มต้นต้องดีพอที่ผู้ใช้ไม่ต้องแตะ; ห้ามแก้ด้วย option ที่ต้องพิมพ์

## หน้าที่ของผู้ใช้
- สร้าง repo หรืออนุญาตให้ใช้ gh, ติดตั้งด้วย AltServer, อนุญาตไมค์
- ทดสอบแล้วส่ง log หรือไฟล์ WAV กลับมาเป็นหลักฐาน

## ความเสี่ยงที่ต้องเช็กใน spike
- usbmux ต่อเข้า listener ได้ไหม (ลองทั้ง loopback และทุก interface)
- driver ที่ต้องใช้กับ pymobiledevice3 และ AltServer
- iPad ได้ 48 kHz จริงไหม
- แอปอื่นแย่งไมค์

## กฎการทำงาน
- อ่าน/ค้น/วิเคราะห์ได้ทันที แต่ทุกการเปลี่ยนสถานะต้องเสนอแผน A1, A2, ... ก่อน
  แล้วรอวลี "Let's do it ทำได้เลยย" ตรงตัวในข้อความล่าสุด
- คำว่า ok / ได้ / ลุย / เอาเลย ไม่นับเป็นการอนุมัติ
- ติดตั้ง/ถอนแพ็กเกจ, git push, ลบไฟล์ = แผนเดี่ยว อนุมัติแยกทุกครั้ง
- เกิด error: หยุด ตรวจแบบอ่านอย่างเดียว รายงานผลจริง ห้าม retry/rollback เอง
- ทุกคำตอบขึ้นต้นด้วยสรุปสั้น ใช้ภาษาไทย ศัพท์เทคนิคเป็นอังกฤษได้
- ห้ามอ้างว่าสำเร็จถ้าไม่มีหลักฐาน

## Git
- author: Zintrea <boonyapatkittichonthawat@gmail.com> (ตั้งใน repo config ก่อน commit แรก)
- ห้ามใช้ Claude เป็น author, ห้ามใส่ Co-Authored-By / Claude-Session / "Generated with Claude Code"
- commit แรกอยู่บน main ได้ หลังจากนั้นทำงานบน branch `dev`
- 1 ฟีเจอร์ = 1 branch `feat/<ชื่อ>` แตกจาก `dev`; merge เข้า `dev` หลังผู้ใช้ทดสอบ ipa ของ branch นั้นผ่านเท่านั้น (merge/push เป็นแผนแยก)
- GitHub: `Zintrea/ipad-usb-mic` (public)
