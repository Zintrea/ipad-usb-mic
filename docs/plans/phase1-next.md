# งานต่อ: แผน 3.1, 4, 5 (เฟส 1 spike)

Repo: `C:\Host\02 Projects\13 Ipadmic`, branch `dev`
ทำตาม CLAUDE.md (execution gate): เสนอทีละแผน, รอวลีอนุมัติแยกทุกแผน, ห้ามทำข้ามแผน
เกิด error: หยุด, ตรวจแบบอ่านอย่างเดียว, รายงาน output จริง, ห้าม retry/แก้เอง

## ข้อเท็จจริงที่ตรวจแล้ว (ไม่ต้องตรวจซ้ำ)
- `py -3.11` ใช้ไม่ได้ แต่มี Python 3.11 อยู่แล้วที่
  `C:\Users\boony\AppData\Roaming\uv\python\cpython-3.11.15-windows-x86_64-none\python.exe`
  → ไม่ต้องติดตั้ง Python เพิ่ม
- `windows/spike_receiver.py` ผ่านการตรวจ syntax แล้ว
- `ios/project.yml` ขาด 3 key ใน `info.properties` (แก้ในแผน 3.1)

---

## แผน 3.1: เติม Info.plist keys ที่ขาด

### A1. แก้ `ios/project.yml`
ใต้บรรทัด `        UILaunchScreen: {}` (indent 8 space) เพิ่ม 3 บรรทัด indent 8 space เท่ากัน:

```yaml
        NSMicrophoneUsageDescription: "Used to send your voice to the computer over USB."
        NSLocalNetworkUsageDescription: "Accepts the connection from the computer over USB."
        UIBackgroundModes: [audio]
```

ตรวจ:
```
Select-String -Path ios/project.yml -Pattern "NSMicrophoneUsageDescription|NSLocalNetworkUsageDescription|UIBackgroundModes"
```
ต้องเจอครบ 3 บรรทัด ไม่ครบ = หยุดและรายงาน

### A2. LOG.md
ใต้หัวข้อวันที่ปัจจุบัน (สร้างหัวข้อใหม่ถ้ายังไม่มี) เพิ่ม 1 รายการ:
- ทำอะไร: เติม NSMicrophoneUsageDescription, NSLocalNetworkUsageDescription, UIBackgroundModes ใน `ios/project.yml`
- ทำไม: ข้อความแผนถูกตัดตอนวาง ทำให้ key หาย
- ปัญหาที่ป้องกัน: แอป crash ตอนขอใช้ไมค์ / iOS อาจบล็อกการต่อจากคอม / เสียงหยุดตอนล็อกจอ
- บทเรียน: เก็บแผนเป็นไฟล์ใน repo (`docs/plans/`) แทนการวางข้อความ

### A3. Commit
```
git add ios/project.yml LOG.md
git commit -m "fix: add missing Info.plist keys (mic, local network, background audio)"
```
ตรวจ: `git log --format="%h %an %s" -1` → author = Zintrea, ห้ามมี Co-Authored-By

---

## แผน 4: สร้าง venv + ติดตั้งแพ็กเกจ Python (เสี่ยงสูง แผนเดี่ยว)

### A1. สร้าง venv
```
& "C:\Users\boony\AppData\Roaming\uv\python\cpython-3.11.15-windows-x86_64-none\python.exe" -m venv "windows\.venv"
```
ตรวจ: `windows\.venv\Scripts\python.exe --version` → `Python 3.11.15`

### A2. ติดตั้ง
```
windows\.venv\Scripts\python.exe -m pip install -r windows\requirements.txt
```
ตรวจ: `windows\.venv\Scripts\python.exe -m pip list` → รายงานเวอร์ชัน pymobiledevice3, sounddevice, numpy

### A3. ตรวจ API pymobiledevice3 (อ่านอย่างเดียว)
```
windows\.venv\Scripts\python.exe -c "import inspect, pymobiledevice3.usbmux as u; print(inspect.signature(u.select_device)); print(inspect.signature(u.MuxDevice.connect))"
```
- เทียบกับโค้ดใน `windows/spike_receiver.py` ที่เรียก `select_device()` และ `dev.connect(port)`
- ตรง → รายงานว่าตรง
- ไม่ตรงหรือ import ล้ม → **ห้ามแก้โค้ดเอง** รายงาน output แล้วเสนอแผนแก้แยก

### A4. ตรวจอุปกรณ์เสียง (อ่านอย่างเดียว ไม่ต้องต่อ iPad)
```
windows\.venv\Scripts\python.exe windows\spike_receiver.py --list-devices
```
ต้องเห็น "CABLE Input (VB-Audio Virtual Cable)" ใต้ hostapi WASAPI → รายงานบรรทัดนั้นตามจริง

### A5. ตรวจว่า git ไม่เห็น venv
`git status --short` → ต้องไม่มี `windows/.venv` (อยู่ใน .gitignore แล้ว)

ไม่ทำในแผนนี้: ไม่ commit (ไม่มีไฟล์ที่ track เปลี่ยน), ไม่ push, ไม่ติดตั้งอะไรนอก venv

---

## แผน 5: push dev + รอผล CI (เสี่ยงสูง แผนเดี่ยว)
เงื่อนไขก่อนเริ่ม: แผน 3.1 commit แล้ว และ `git status` สะอาด

### A1. Push
```
git push -u origin dev
```

### A2. ดูผล CI
```
gh run list --branch dev --limit 1
gh run watch <run-id> --exit-status
```

### A3. ถ้าผ่าน
```
gh run download <run-id> --name IpadMic-ipa --dir build\ci
```
ตรวจ: `Get-Item build\ci\IpadMic.ipa | Select-Object Name,Length` → มีไฟล์และขนาด > 0 (`build/` อยู่ใน .gitignore แล้ว)

### A4. ถ้าล้ม
```
gh run view <run-id> --log-failed
```
รายงานประมาณ 30 บรรทัดสุดท้ายที่มี error → **ห้ามแก้หรือ push ซ้ำเอง** เสนอแผนแก้แยก

### A5. LOG
เพิ่มผล CI (run id, ผ่านหรือไม่ผ่าน, ขนาด .ipa) ลง LOG.md แล้ว commit `docs: log CI result`
ยังไม่ต้อง push commit นี้ (รวมไป push ครั้งถัดไป)

---

## หลังแผน 5: สิ่งที่ผู้ใช้ทำเอง (โมเดลแค่บอกขั้นตอน ห้ามทำแทน)
1. AltServer: taskbar **^** → Shift+คลิกไอคอนเพชร → Sideload .ipa → เลือก iPad → `build\ci\IpadMic.ipa` → ใส่ Apple ID สำรอง
   (Sideloadly/iloader ใช้ไม่ได้แล้ว เหตุผลดู [GUIDE ข้อ 8](../GUIDE.md#8-ทำไมใช้-altserver-ไม่ใช้-sideloadly--iloader))
2. iPad:
   - Settings → Privacy & Security → Developer Mode → เปิด (เครื่องจะรีสตาร์ต)
   - Settings → General → VPN & Device Management → Trust
3. เสียบสาย USB → กด "Trust This Computer" ถ้ามีขึ้นมา
4. เปิดแอป iPad Mic → START → ต้องเห็นจุดเหลือง "รอคอมต่อ..."
5. บนคอม:
   ```
   windows\.venv\Scripts\python.exe windows\spike_receiver.py --wav test.wav
   ```
   ผลที่คาด: ขึ้น "header ถูกต้อง (IPMC v1, mono, 48000 Hz, Float32)" และแอปเปลี่ยนเป็นจุดเขียว
   ปล่อย 10 วินาที แล้วกด Ctrl+C
6. ตรวจไฟล์:
   ```
   windows\.venv\Scripts\python.exe windows\spike_receiver.py --check test.wav
   ```
   ผลที่คาด: "พบความถี่หลัก ~440 Hz" ตามด้วย "ผ่าน"
7. ส่ง output ข้อ 5 และ 6 กลับมาเป็นหลักฐาน
   ถ้าข้อ 5 ต่อไม่ได้ → ลองตั้ง `bindLoopbackOnly = true` ใน `SineServer.swift`
   (ต้องเป็นแผนแยก และต้องรัน CI ใหม่)
