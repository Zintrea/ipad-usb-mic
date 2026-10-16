# LOG

ดูภาพรวมและวิธีใช้ที่ [README.md](README.md)

## 2026-10-16
- เริ่มโปรเจกต์: สร้าง repo ในเครื่อง + โครงไฟล์ (`.gitignore`, `README.md`, `LOG.md`, `SPEC.md`)
- ตัดสินใจ:
  - ส่งเสียงเป็น Float32 mono 48 kHz (ไม่ใช้ Int16/converter) เพื่อคุณภาพและความง่าย
  - jitter buffer เริ่ม 30 ms + ชดเชย clock drift ด้วย `np.interp`
  - repo บน GitHub: public, ชื่อ `ipad-usb-mic`, branch ทำงาน `dev`
- ข้อสังเกต: ยังไม่พบ service ชื่อ "Apple Mobile Device Service" ด้วยการค้นแบบอ่านอย่างเดียว (แอป Apple Devices จาก Store อาจใช้ชื่ออื่น) → ตรวจในเฟส 1
