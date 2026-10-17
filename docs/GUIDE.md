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
| sideload | ติดตั้งแอปเองโดยไม่ผ่าน App Store (ใช้ AltServer ดูเหตุผลที่ข้อ 8) |
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
3. **ลงด้วย AltServer** (ติดตั้งครั้งแรกดูข้อ 8)
   - เสียบ iPad ปลดล็อกจอ
   - ที่ taskbar กด **^** (Show hidden icons) → **กด Shift ค้าง** แล้วคลิกซ้ายไอคอนรูปเพชร → **Sideload .ipa** → เลือก iPad → เลือก `build\ci\IpadMic.ipa`
   - ใส่ Apple ID **สำรอง** (ไม่ใช้บัญชีหลัก) รอจนขึ้นว่าติดตั้งสำเร็จ
   - อย่ากด "Install AltStore" (นั่นคือลงแอป AltStore ไม่ใช่แอปเรา)
   - iPad: เปิด Developer Mode และ Settings → General → VPN & Device Management → trust profile
   - Apple ID ฟรีเซ็นได้ 7 วัน หมดอายุแล้วต้องทำข้อนี้ซ้ำ
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
| เปิด AltServer แล้วไม่มีหน้าต่าง | ปกติ AltServer อยู่ใน tray เท่านั้น กด **^** ที่ taskbar อย่ากดเปิดซ้ำ (จะรันซ้อนหลายตัว) |

### 8. ทำไมใช้ AltServer (ไม่ใช้ Sideloadly / iloader)

สถานะ 2026-10-17: ติดตั้งสำเร็จด้วย AltServer หลังลองเครื่องมืออื่นไม่ผ่านนานกว่า 12 ชั่วโมง

**อาการที่เจอ**

| เครื่องมือ | error |
|---|---|
| Sideloadly (เวอร์ชันล่าสุด) | `GSA returned a non-plist response (HTTP 503 Service Temporarily Unavailable)` |
| iloader (isideload 0.4.6) | `503 Service Temporarily Unavailable ... gsa.apple.com/grandslam/GsService2` |
| iloader | anisette `502 Bad Gateway ... mac-ani.jkcoxson.com/v3/client_info` และ `unknown session (-45025)` |

**สิ่งที่ลองแล้วไม่ช่วย:** อัปเดต iloader 2.3.9+, Reset Anisette, เว้นระยะ 30-60 นาที, เปลี่ยนเครือข่าย/hotspot, เปลี่ยน Apple ID, แก้ hosts, ติดตั้ง iCloud

**สาเหตุ**
1. ตั้งแต่ต้นเดือนกันยายน 2026 Apple ตอบ 503 กับการล็อกอินที่ระบุตัวเป็น Xcode (`com.apple.dt.Xcode` ใน header `X-MMe-Client-Info`) ซึ่ง Sideloadly และ iloader ใช้ จึงเปลี่ยนบัญชีหรือ IP ก็ไม่ช่วย ([AltStore PR #1790](https://github.com/altstoreio/AltStore/pull/1790), [iloader PR #700](https://github.com/nab138/iloader/pull/700))
2. iloader พึ่ง anisette server ภายนอก ซึ่งล่มเป็นช่วง ๆ (วัดได้ 200/502 สลับกัน)

**ทำไม AltServer ผ่าน:** ระบุตัวเป็น `akd` ซึ่ง Apple ยังไม่บล็อก และสร้าง anisette ในเครื่องผ่าน iTunes/iCloud ไม่ต้องพึ่ง server ภายนอก (ข้อหลังยังไม่ได้ตรวจยืนยัน)

**ติดตั้งครั้งแรก (ทำแล้วบนเครื่องนี้)**
1. ถอน iTunes เวอร์ชัน Microsoft Store: `Get-AppxPackage AppleInc.iTunes | Remove-AppxPackage` (AltServer ใช้เวอร์ชัน Store ไม่ได้)
2. ติดตั้ง iTunes 64-bit จาก `https://www.apple.com/itunes/download/win64` (ตัวติดตั้งเซ็นโดย Apple Inc.) ผลที่ควรเห็น: Installed apps มี `iTunes 12.13.11.1` หรือใหม่กว่า
3. iCloud ต้องเป็นเวอร์ชันเว็บ (เครื่องนี้มี 7.21)
4. ติดตั้ง AltServer จาก `https://cdn.altstore.io/file/altstore/altinstaller.zip` แตก zip แล้วรัน `altinstaller.msi` (ไฟล์ไม่มีลายเซ็นดิจิทัล; SHA256 ที่ใช้: `944186A28493B628A7702C514155140D530DFADC31F4279033AE576F1403CD5F`) ผลที่ควรเห็น: มี `C:\Program Files (x86)\AltServer\AltServer.exe` และไอคอนรูปเพชรใน tray ที่เห็นชื่อ iPad ในเมนู Install AltStore

**ถ้าวันหนึ่ง AltServer เจอ 503 ด้วย:** แปลว่า Apple บล็อก `akd` แล้ว ไม่ต้องลองซ้ำรัว ๆ (เสี่ยงบัญชีถูกล็อก -20209) ทางที่เหลือคือรอเครื่องมือออกตัวแก้ หรือสมัคร Apple Developer Program แล้วให้ CI เซ็นเอง
