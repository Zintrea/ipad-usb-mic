# แผนเฟส 2: ไมค์จริง จนใช้งานได้จริง

Repo: `C:\Host\02 Projects\13 Ipadmic`, branch `dev`
ทำตาม CLAUDE.md (execution gate): เสนอทีละแผน, รอวลีอนุมัติแยกทุกแผน, ห้ามทำข้ามแผน
เกิด error: หยุด, ตรวจแบบอ่านอย่างเดียว, รายงาน output จริง, ห้าม retry/แก้เอง
Commit: author Zintrea, ห้ามมี Co-Authored-By (SPEC ข้อ Git)

## เกณฑ์ผ่านเฟส 2 (จาก SPEC)
| # | ทดสอบ | หลักฐาน |
|---|---|---|
| T1 | ล็อกจอ iPad 10 นาที | log receiver: `สะดุด 0` ตลอด 10 นาที |
| T2 | รันต่อเนื่อง 1 ชั่วโมง | log ทุก 10 วินาที: buffer อยู่ในช่วงเป้า ±10 ms หลังนาทีแรก, drift ppm นิ่ง |
| T3 | ถอดสายแล้วเสียบใหม่ / กด STOP แล้ว START | log: `รอ iPad...` แล้วกลับมา `header ถูกต้อง` เองโดยไม่ต้องรันใหม่ |
| T4 | ร้องเพลงอัดจาก CABLE Output | ไฟล์ WAV ฟังแล้วไม่สะดุด, แถบระดับไม่แดง |

## ข้อเท็จจริงที่ตรวจแล้ว (ไม่ต้องตรวจซ้ำ)
- เส้นทาง iPad → usbmux → Python ใช้ได้ (เฟส 1, bind ทุก interface ใช้ได้)
- pymobiledevice3 11.33.0: `select_device` / `connect` เป็น async, socket ต้อง `setblocking(True)`
- CABLE Input อยู่บน WASAPI 48000 Hz
- โปรโตคอล header 16 byte ใช้ต่อได้ไม่ต้องเปลี่ยน (ขนาดก้อน PCM ไม่ได้อยู่ใน header)

## ความเสี่ยงที่ต้องดูตอนทดสอบจริง
- R1 tap ของ AVAudioEngine มักไม่ทำตาม `bufferSize` (อาจได้ก้อนละ ~100 ms) ถ้าก้อนใหญ่กว่า 20 ms
  buffer 30 ms จะสะดุด → แอปแสดงขนาดก้อนจริงบนจอ ถ้าเกิน = หยุดและรายงาน
  (ทางเลือก: เปลี่ยนเป็น `AVAudioSinkNode` หรือเพิ่ม `--buffer-ms`)
- R2 iPad อาจไม่ได้ 48 kHz → แอปแสดง error ตาม SPEC (ไม่ทำตัวแปลง)
- R3 route change อาจยิงตอนเริ่ม session (reason `.categoryChange`) → หยุดเฉพาะ reason
  `.oldDeviceUnavailable` / `.newDeviceAvailable`
- R4 ทุกรอบ CI + AltServer ใช้เวลาและโควตา App ID → รวมงาน iOS ให้จบใน build เดียวให้มากที่สุด

---

## แผน 2.1: ตัวรับ Windows (ทำได้เลย ไม่ต้องใช้ iPad)

### A1. เปลี่ยนชื่อไฟล์
`git mv windows/spike_receiver.py windows/receiver.py` (ไม่ใช่ spike แล้ว)

### A2. Test ก่อน (TDD): `windows/test_receiver.py` (unittest ใน stdlib ไม่เพิ่ม dependency)
จำลองไม่ต้องใช้ฮาร์ดแวร์:
- ผู้ส่งเร็วกว่าผู้เล่น +100 ppm (และ -100 ppm) ส่งก้อนละ 480 frame มี jitter สุ่ม ±3 ms
- ผู้เล่นดึงครั้งละ 480 frame จำลอง 10 นาที
- ต้องผ่าน: ไม่มี underrun หลังเริ่มเล่น, buffer นาทีสุดท้ายอยู่ในเป้า ±5 ms,
  ppm ที่ประเมินได้อยู่ในช่วง 100 ± 30 (เครื่องหมายถูกทิศ)
- sine 1 kHz ผ่าน resampler แล้วความถี่ไม่เพี้ยนเกิน 1 Hz (กันคลิก/รอยต่อผิด)
รัน: `windows\.venv\Scripts\python -m unittest windows/test_receiver.py` → ต้อง FAIL ก่อนแก้โค้ด

### A3. drift compensation ใน `Jitter` (`receiver.py`)
- เก็บ buffer เป็น float32 (np.ndarray) แทน bytearray + ตำแหน่งอ่านแบบเศษส่วน
- ทุก `pull(frames)`: level เฉลี่ยแบบ EMA (τ ≈ 1 วินาที) → `ppm = clamp(Kp * (level - target) / target, ±1000)`
  แล้วอ่านด้วยอัตรา `r = 1 + ppm/1e6` ผ่าน `np.interp` (ไม่แทรก/ตัด sample)
- เก็บ sample สุดท้ายของรอบก่อนไว้ interp ต่อ เพื่อไม่ให้มีรอยต่อ
- shortcut: ใช้แค่ P controller (มี offset คงที่เล็กน้อยตาม drift), เปลี่ยนเป็น PI ถ้า T2 ไม่ผ่าน
- overflow (เกิน 4 เท่าเป้า) ยังตัดของเก่าเหมือนเดิม
รัน test ใน A2 → ต้องผ่าน

### A4. ต่อใหม่อัตโนมัติ
- แยก `run()` เป็น: เปิด output stream ครั้งเดียว + loop รอบนอก `while True: session()`
- `session()`: หา iPad → connect → ตรวจ header → รับข้อมูล
- ไม่พบ iPad / ต่อไม่ได้ / ปิด / ไม่มีข้อมูลเกิน 3 วินาที → log `รอ iPad...` → reset jitter (`playing=False`) → รอ 1 วินาทีแล้วลองใหม่
- ระหว่างรอ output เล่นเงียบ (DAW ไม่ต้องเลือกอุปกรณ์ใหม่)
- header ไม่ตรง = จบโปรแกรมพร้อมข้อความ (เวอร์ชันแอปไม่ตรง ลองใหม่ไม่ช่วย)
- Ctrl+C จบ, ปิด WAV ให้สมบูรณ์เหมือนเดิม

### A5. log ทุก 10 วินาที
`buffer 31 ms | สะดุด 0 | ล้น 0 | drift +42 ppm | ก้อนใหญ่สุด 10 ms`
(ก้อนใหญ่สุด = ช่วงห่างสูงสุดระหว่างข้อมูลเข้า ใช้ตรวจ R1 จากฝั่ง PC ด้วย)

### A6. `windows/start.bat`
```bat
@echo off
cd /d %~dp0
.venv\Scripts\python receiver.py %*
pause
```

### A7. ตรวจ + commit
- `python -m unittest windows/test_receiver.py` ผ่าน
- `receiver.py --list-devices` และ `--check` ยังทำงาน
- รันโดยไม่เสียบ iPad: เห็น `รอ iPad...` ซ้ำทุก ~1 วินาที, Ctrl+C จบได้
- LOG.md + commit `feat: receiver drift compensation and auto reconnect`

---

## แผน 2.2: แอป iPad ใช้ไมค์จริง

### A1. `git mv ios/IpadMic/SineServer.swift ios/IpadMic/MicServer.swift`
คงส่วน TCP (listener, accept, header, รับ client ทีละตัว, backToWaiting) ไว้เหมือนเดิม
ลบ timer + sine ออก

### A2. เสียงจากไมค์
- `start()`: ขอสิทธิ์ `AVAudioApplication.requestRecordPermission` → ปฏิเสธ = state `.error("ไม่ได้รับอนุญาตใช้ไมค์")`
- AVAudioSession: `.record`, mode `.measurement`, `setPreferredSampleRate(48000)`,
  `setPreferredIOBufferDuration(0.005)`, `setActive(true)`
- ตรวจ `session.sampleRate` และ format ของ `inputNode` ≠ 48000 → `.error("iPad ให้ \(rate) Hz ไม่ใช่ 48000")` (R2)
- `inputNode.installTap(bufferSize: 480, format: inputFormat)` → เอาแค่ channel 0
  (`floatChannelData[0]`) copy เป็น `Data` แล้ว `queue.async` ส่ง
- ไม่มี client = ทิ้ง sample แต่ engine รันต่อ (กันแอปถูก suspend ตอนล็อกจอ)
- engine รันตั้งแต่ START จนกด STOP ไม่ผูกกับการต่อของ client

### A3. ระดับเสียง + ขนาดก้อน
- ใน tap หา peak ของก้อน, ส่งขึ้น main ไม่เกิน ~20 ครั้ง/วินาที (`@Published level`)
- `@Published chunkMs` = ขนาดก้อนจริงล่าสุด (R1)

### A4. interruption / route change
- `AVAudioSession.interruptionNotification` (type `.began`) และ `routeChangeNotification`
  (เฉพาะ reason ใน R3) → หยุด engine + ปิด listener → state `.interrupted`

### A5. UI (`ContentView.swift`)
- State: `.stopped / .waiting / .streaming / .interrupted / .error(String)`
  ข้อความ: หยุดอยู่ / รอคอมต่อ... / กำลังส่งเสียง / "Interrupted – กด Start ใหม่" / ข้อความ error
- แถบระดับเสียง (`ProgressView` หรือ `Capsule` ตามความกว้าง) สีเขียว, peak ≥ -3 dBFS (0.71) เป็นแดง
- footnote: `ก้อนละ X ms` แทน "โหมดทดสอบ: 440 Hz"
- `IpadMicApp.swift`: เปลี่ยน `SineServer` → `MicServer`

### A6. ตรวจ + commit
- ไม่มี Mac → ตรวจ syntax ไม่ได้ในเครื่อง, ตรวจด้วย CI ในแผน 2.3
- LOG.md + commit `feat: stream real microphone with level meter`

---

## แผน 2.3: push + CI (เสี่ยงสูง แผนเดี่ยว)
- `git push origin dev` → `gh run watch` ต้องจบด้วยเครื่องหมายถูก
- CI fail = หยุด รายงาน log จริง (`gh run view --log-failed`) ไม่แก้เอง
- `gh run download -n IpadMic-ipa -D build\ci` → มี `build\ci\IpadMic.ipa`

## แผน 2.4: ติดตั้ง + ทดสอบจริง (ผู้ใช้ทำ แล้วส่ง log/WAV กลับ)
1. ลง `IpadMic.ipa` ด้วย AltServer (GUIDE ข้อ 5.3) → เปิดแอป → กด START → อนุญาตไมค์
2. ดูจอ: ต้องเห็น `ก้อนละ ... ms` ≤ 20 ms (เกิน = หยุด รายงาน R1)
3. `windows\start.bat --wav test.wav` แล้วทำ T1-T4 ตามลำดับ เก็บ log ด้วย
   `windows\start.bat 2>&1 | Tee-Object phase2.log` (PowerShell)
4. T4 อัดจาก CABLE Output (DAW หรือ Audacity, 48 kHz) ร้องเพลง 1 นาที
5. ส่ง `phase2.log` + WAV กลับมาตรวจ

## แผน 2.5: เอกสาร + ปิดเฟส
- GUIDE บทที่ 2 (ไมค์จริง, drift ทำงานยังไง, วิธีทดสอบ T1-T4, ปัญหาที่เจอจริง), แก้ข้อ 3/4/5 ที่อ้าง `spike_receiver.py` และ "ก้อนละ 480 sample"
- SPEC.md: แก้เฉพาะจุดที่ผลจริงขัด (เช่น R1)
- LOG.md: ผล T1-T4 พร้อมตัวเลขจริง
- commit `docs: phase 2 results`

## ไม่ทำในเฟส 2 (ตัดออกโดยตั้งใจ)
ตัวแปลง sample rate, stereo, หลาย client, GUI ฝั่ง Windows, ปรับ gain ในแอป, ติดตั้งเป็น service
