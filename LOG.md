# LOG

ดูภาพรวมและวิธีใช้ที่ [README.md](README.md)

## 2026-10-16
- เริ่มโปรเจกต์: สร้าง repo ในเครื่อง + โครงไฟล์ (`.gitignore`, `README.md`, `LOG.md`, `SPEC.md`)
- ตัดสินใจ:
  - ส่งเสียงเป็น Float32 mono 48 kHz (ไม่ใช้ Int16/converter) เพื่อคุณภาพและความง่าย
  - jitter buffer เริ่ม 30 ms + ชดเชย clock drift ด้วย `np.interp`
  - repo บน GitHub: public, ชื่อ `ipad-usb-mic`, branch ทำงาน `dev`
- ข้อสังเกต: ยังไม่พบ service ชื่อ "Apple Mobile Device Service" ด้วยการค้นแบบอ่านอย่างเดียว (แอป Apple Devices จาก Store อาจใช้ชื่ออื่น) → ตรวจในเฟส 1

## 2026-10-17
- สร้าง branch `dev` และโครงเฟส 1 ทั้งหมด (ดู [GUIDE บทที่ 1](docs/GUIDE.md#บทที่-1-เฟส-1-spike--ipad-ส่งเสียง-sine-440-hz-ผ่าน-usb))
  - **ทำอะไร:** แอป iPad ส่ง sine 440 Hz (`ios/`), CI (`.github/workflows/build.yml`), ตัวรับ Python (`windows/spike_receiver.py`), GUIDE บทที่ 1
  - **ทำไม:** พิสูจน์เส้นทาง iPad → usbmux → Python ก่อนใช้ไมค์จริง (เฟส 2)
  - **ปัญหาที่เจอ:** (1) `project.yml` ในแผนมีบรรทัด `UIL` ถูกตัดค้าง (2) โค้ดส่วน timer/สร้างเสียงใน SineServer ในแผนถูกตัด (3) `py -3.11` ไม่มีในเครื่อง (มีแต่ Python 3.12.10)
  - **วิธีแก้:** (1) ใช้ `UILaunchScreen: {}` (2) เขียนเองตามโปรโตคอล: timer 10 ms, phase ต่อเนื่อง, amplitude 0.5 (3) ตรวจ syntax ด้วย `py -3` แทน; แผน 4 ต้องติดตั้ง Python 3.11 ก่อน
- ยังไม่ได้ตรวจ: CI ยังไม่ได้รัน, ยังไม่ได้ติดตั้ง `pymobiledevice3` จึงยังไม่ได้ตรวจ signature ของ `select_device` / `MuxDevice.connect` (ต้องตรวจในแผน 4 แล้วแก้ตามจริง), ยังไม่ได้ทดสอบกับ iPad
- เติม Info.plist keys ที่ขาด (ดู [GUIDE บทที่ 1](docs/GUIDE.md))
  - **ทำอะไร:** เติม `NSMicrophoneUsageDescription`, `NSLocalNetworkUsageDescription`, `UIBackgroundModes` ใน `ios/project.yml`
  - **ทำไม:** ข้อความแผนถูกตัดตอนวาง ทำให้ key หาย
  - **ปัญหาที่ป้องกัน:** แอป crash ตอนขอใช้ไมค์ / iOS อาจบล็อกการต่อจากคอม / เสียงหยุดตอนล็อกจอ
  - **บทเรียน:** เก็บแผนเป็นไฟล์ใน repo (`docs/plans/`) แทนการวางข้อความ
- ผลแผน 4 และ 5 (ดู [GUIDE บทที่ 1](docs/GUIDE.md))
  - **ทำอะไร:** สร้าง `windows/.venv` (Python 3.11.15), ติดตั้ง requirements (pymobiledevice3 11.33.0, sounddevice 0.5.6, numpy 2.4.6), push `dev`, รัน CI
  - **ผลตรวจ:** signature ตรงกับโค้ด: `select_device(udid=None, connection_type=None, usbmux_address=None)` และ `MuxDevice.connect(self, port, usbmux_address=None) -> socket`; `--list-devices` เจอ `CABLE Input (VB-Audio Virtual Cable)` บน WASAPI 48000 Hz
  - **CI:** run 38947126453 ผ่าน (48 วินาที) ได้ `IpadMic.ipa` ขนาด 25010 byte มี warning เรื่อง Node.js 20 deprecated ของ actions/checkout@v4 และ upload-artifact@v4 (ยังไม่กระทบ)
  - **ยังไม่ได้ตรวจ:** ติดตั้งลง iPad, การต่อผ่าน usbmux จริง, WAV 440 Hz
- เปลี่ยนเครื่องมือ sideload เป็น AltServer (ดู [GUIDE ข้อ 8](docs/GUIDE.md#8-ทำไมใช้-altserver-ไม่ใช้-sideloadly--iloader))
  - **ทำอะไร:** ถอน iTunes เวอร์ชัน Store, ลง iTunes 12.13.11.1 จากเว็บ Apple, ลง AltServer แล้วติดตั้ง `IpadMic.ipa` ลง iPad สำเร็จ แอปเปิดได้
  - **ทำไม:** Sideloadly และ iloader ล็อกอิน Apple ไม่ผ่าน (grandslam 503, anisette 502, -45025) นานกว่า 12 ชั่วโมง เพราะ Apple บล็อกตัวระบุ Xcode
  - **แก้เอกสาร:** GUIDE ข้อ 5.3 และ 8, `docs/plans/phase1-next.md`, คอมเมนต์ `build.yml`
  - **ยังไม่ได้ตรวจ:** การต่อผ่าน usbmux จริง, WAV 440 Hz; การที่ไม่พบ service "Apple Mobile Device" ยังไม่ได้แก้ แต่ AltServer เห็น iPad แล้ว
