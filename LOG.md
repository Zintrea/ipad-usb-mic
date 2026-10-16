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
