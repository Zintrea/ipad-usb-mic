# คู่มือ iPad Mic

ภาพรวมโปรเจกต์ดู [SPEC.md](../SPEC.md) · บันทึกการเปลี่ยนแปลงดู [LOG.md](../LOG.md)

## บทที่ 1: เฟส 1 Spike — iPad ส่งเสียง sine 440 Hz ผ่าน USB

เป้าหมายของบทนี้: พิสูจน์ว่า "เสียงวิ่งจาก iPad ผ่านสาย USB เข้า Windows ได้จริง" ด้วยเสียงทดสอบ (โทนความถี่ 440 Hz) ก่อนจะใช้ไมค์จริง

### 1. ภาพรวม

iPad ทำตัวเป็นไมค์ USB เองไม่ได้ เพราะ iPadOS ไม่รองรับการเป็นอุปกรณ์เสียง USB (USB Audio Class) เมื่อเสียบสายเข้าคอม iPad เป็นได้แค่ "อุปกรณ์ที่ถูกควบคุม" ดังนั้นเราต้องมีแอปบน iPad และโปรแกรมบน Windows ช่วยกัน

```
iPad (แอป)  --TCP พอร์ต 7777-->  usbmux  -->  Python  -->  VB-Cable  -->  DAW / OBS / Discord
 สร้างเสียง                    (ท่อผ่านสาย USB)   รับ+บัฟเฟอร์   ไมค์เสมือน      เลือก "CABLE Output"
```

### 2. ความรู้พื้นฐาน

| คำ | ความหมายแบบสั้น |
|---|---|
| sample rate | จำนวนค่าเสียงต่อวินาที เราใช้ 48000 (48 kHz) |
| Float32 | เก็บค่าเสียง 1 ค่าเป็นเลขทศนิยม 4 byte ช่วง -1.0 ถึง 1.0 |
| buffer | ที่พักเสียงก่อนเล่น เพื่อรับมือจังหวะข้อมูลมาไม่สม่ำเสมอ |
| underrun | เล่นเสียงเร็วกว่าที่ข้อมูลมา buffer หมด ได้ยินเป็นเสียงสะดุด |
| TCP / port | วิธีส่งข้อมูลแบบไม่ตกหล่น / "เลขห้อง" ของโปรแกรม ที่นี่คือ 7777 |
| usbmux | บริการของ Apple ที่ทำท่อ TCP ผ่านสาย USB (มากับแอป Apple Devices) |
| sideload | ติดตั้งแอปเองโดยไม่ผ่าน App Store (ใช้ Sideloadly) |
| CI | ให้เครื่องบน GitHub build แอปให้อัตโนมัติ เพราะเราไม่มี Mac |

### 3. โครงไฟล์ของ repo

| ไฟล์ | หน้าที่ |
|---|---|
| `SPEC.md` | สเปกและการตัดสินใจ |
| `LOG.md` | บันทึกตามวันที่ |
| `ios/project.yml` | คำอธิบายโปรเจกต์ให้ XcodeGen สร้าง `.xcodeproj` |
| `ios/IpadMic/IpadMicApp.swift` | จุดเริ่มต้นของแอป |
| `ios/IpadMic/ContentView.swift` | หน้าจอ: สถานะ + ปุ่ม START/STOP |
| `ios/IpadMic/SineServer.swift` | เซิร์ฟเวอร์ TCP + สร้างเสียง 440 Hz |
| `.github/workflows/build.yml` | CI: build แล้วได้ไฟล์ `.ipa` |
| `windows/requirements.txt` | แพ็กเกจ Python ที่ต้องใช้ |
| `windows/spike_receiver.py` | ตัวรับเสียงฝั่ง Windows |

### 4. โปรโตคอล

ตอนต่อสำเร็จ iPad ส่ง header 16 byte ครั้งเดียว (little-endian) จากนั้นส่ง Float32 mono ต่อเนื่อง ก้อนละ 480 sample (10 ms = 1920 byte)

| byte | ขนาด | ฟิลด์ | ค่า |
|---|---|---|---|
| 0–3 | 4 | magic | `"IPMC"` |
| 4–5 | 2 | version | 1 |
| 6–7 | 2 | channels | 1 |
| 8–11 | 4 | sampleRate | 48000 |
| 12–13 | 2 | format | 1 (Float32) |
| 14–15 | 2 | reserved | 0 |

ตัวอย่าง hex จริง:

```
49 50 4D 43  01 00  01 00  80 BB 00 00  01 00  00 00
 I  P  M  C   v=1    ch=1   48000        fmt=1  rsv=0
```

48000 = 0xBB80 จึงเขียนแบบ little-endian เป็น `80 BB 00 00`

### 5. ลองทำเองทีละขั้น

> หมายเหตุ: ณ ตอนเขียน ยังไม่ได้รัน CI หรือทดสอบกับ iPad จริง "ผลที่ควรเห็น" คือสิ่งที่คาดไว้

1. **push** (ครั้งแรกต้องให้เจ้าของ repo อนุมัติ)
   ```
   git push -u origin dev
   gh run watch
   ```
   ควรเห็น workflow `build-ios` จบด้วยเครื่องหมายถูก
2. **ดาวน์โหลด artifact** `gh run download -n IpadMic-ipa` ควรได้ไฟล์ `IpadMic.ipa`
3. **ลงด้วย Sideloadly** เสียบ iPad, เปิด Sideloadly, เลือก `IpadMic.ipa`, ใส่ Apple ID แล้วกด Start จากนั้นเปิด Developer Mode และ trust profile บน iPad
4. **สร้าง venv และติดตั้ง** (ต้องมี Python 3.11)
   ```
   py -3.11 -m venv windows\.venv
   windows\.venv\Scripts\pip install -r windows\requirements.txt
   ```
5. **รันตัวรับ** เปิดแอปบน iPad กด START (สถานะเหลือง "รอคอมต่อ...") แล้ว
   ```
   windows\.venv\Scripts\python windows\spike_receiver.py --no-play --wav out.wav
   ```
   ควรเห็น `header ถูกต้อง (IPMC v1, mono, 48000 Hz, Float32)` และ log ทุก 10 วินาที บน iPad จุดเปลี่ยนเป็นเขียว กด Ctrl+C เพื่อจบ
6. **ตรวจ** `windows\.venv\Scripts\python windows\spike_receiver.py --check out.wav`
   ควรเห็น `พบความถี่หลัก 440.0 Hz` ตามด้วย `ผ่าน`

ถ้าจะฟังผ่านลำโพงไป VB-Cable ให้ตัด `--no-play` ออก (ตั้ง CABLE Input เป็น 48000 Hz ก่อน)

### 6. แบบฝึกหัด: เปลี่ยน 440 เป็น 880 Hz

แก้ที่ `ios/IpadMic/SineServer.swift` บรรทัด `private let frequency: Double = 440` เป็น `880` (ถ้าอยากให้ข้อความบนจอตรง แก้ `ios/IpadMic/ContentView.swift` "โหมดทดสอบ: 440 Hz" ด้วย) และแก้ช่วงผ่านใน `check_wav` ของ `windows/spike_receiver.py` (`435 <= freq <= 445`) แล้ว push เพื่อให้ CI build ใหม่

### 7. ปัญหาที่อาจเจอ

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| `ไม่พบ iPad` | เสียบสาย ปลดล็อกจอ กด "Trust This Computer" และตรวจว่าติดตั้งแอป Apple Devices แล้ว |
| ต่อ port 7777 ไม่ได้ | แอปยังไม่ได้กด START หรือ usbmux ต่อ listener แบบทุก interface ไม่ได้ ลองแก้ `bindLoopbackOnly = true` ใน `SineServer.swift` แล้ว build ใหม่ |
| rate ไม่ตรง / เปิดอุปกรณ์ไม่ได้ | ตั้ง CABLE Input เป็น 48000 Hz ใน Sound Control Panel (แท็บ Advanced) |
