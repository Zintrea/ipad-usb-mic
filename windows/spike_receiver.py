"""ตัวรับเสียงจาก iPad (เฟส 1 spike): รับ sine ผ่าน usbmux แล้วเล่นเข้า CABLE Input

โปรโตคอล: header 16 byte (little-endian) "IPMC"|ver u16|ch u16|rate u32|fmt u16|rsv u16
ตามด้วย Float32 mono ต่อเนื่อง ดู docs/GUIDE.md
"""
import argparse
import datetime
import struct
import sys
import threading
import time
import wave

import numpy as np

RATE = 48000
HEADER_FMT = "<4sHHIHH"
HEADER_SIZE = 16  # struct.calcsize(HEADER_FMT)
BYTES_PER_FRAME = 4  # Float32 mono


def log(msg):
    print(f"[{datetime.datetime.now():%H:%M:%S}] {msg}", flush=True)


# ---------- --check : วิเคราะห์ไฟล์ WAV ----------
def check_wav(path):
    with wave.open(path, "rb") as w:
        n, rate, ch = w.getnframes(), w.getframerate(), w.getnchannels()
        raw = w.readframes(n)
    x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch)[:, 0]
    if len(x) == 0:
        print("ไฟล์ว่าง ไม่มีเสียง")
        return 1
    # ใช้ window กัน spectral leakage ไม่งั้นจุดยอดจะกว้างจนความถี่เพี้ยน
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    freq = np.argmax(spec) * rate / len(x)
    print(f"พบความถี่หลัก {freq:.1f} Hz")
    if 435 <= freq <= 445:
        print("ผ่าน")
        return 0
    print("ไม่ผ่าน")
    return 1


# ---------- --list-devices / เลือก output ----------
def list_devices():
    import sounddevice as sd
    apis = sd.query_hostapis()
    for i, d in enumerate(sd.query_devices()):
        if d["max_output_channels"] > 0:
            print(f"[{i}] {d['name']}  ({apis[d['hostapi']]['name']}, "
                  f"{d['max_output_channels']} ch, default {d['default_samplerate']:.0f} Hz)")


def find_output(name):
    """หา device: ใช้ WASAPI เท่านั้น (ตาม SPEC) ชื่อตรงกับ --device หรือมี 'CABLE Input'"""
    import sounddevice as sd
    apis = sd.query_hostapis()
    want = (name or "CABLE Input").lower()
    for i, d in enumerate(sd.query_devices()):
        if d["max_output_channels"] < 1:
            continue
        if "wasapi" not in apis[d["hostapi"]]["name"].lower():
            continue
        if want in d["name"].lower():
            return i
    return None


# ---------- buffer ที่ thread รับกับ callback ใช้ร่วมกัน ----------
class Jitter:
    def __init__(self, target_ms):
        self.buf = bytearray()
        self.lock = threading.Lock()  # สอง thread แก้ bytearray พร้อมกัน ต้องล็อก
        self.target = int(RATE * target_ms / 1000) * BYTES_PER_FRAME
        self.playing = False  # รอให้เต็มเป้าก่อนค่อยเริ่มเล่น
        self.underruns = 0
        self.overflows = 0

    def push(self, data):
        with self.lock:
            self.buf += data
            limit = self.target * 4
            if len(self.buf) > limit:
                # ตัดของเก่า (ให้ขนาดเป็นผลคูณ 4 byte จะได้ไม่เหลือครึ่ง sample)
                drop = (len(self.buf) - self.target) // BYTES_PER_FRAME * BYTES_PER_FRAME
                del self.buf[:drop]
                self.overflows += 1

    def pull(self, frames):
        need = frames * BYTES_PER_FRAME
        with self.lock:
            if not self.playing:
                if len(self.buf) >= self.target:
                    self.playing = True
                else:
                    return np.zeros(frames, dtype=np.float32)
            have = min(need, len(self.buf))
            chunk = bytes(self.buf[:have])
            del self.buf[:have]
            if have < need:
                self.underruns += 1
        out = np.zeros(frames, dtype=np.float32)
        out[: have // BYTES_PER_FRAME] = np.frombuffer(chunk, dtype="<f4")
        return out

    def level_ms(self):
        with self.lock:
            return len(self.buf) / BYTES_PER_FRAME * 1000 / RATE


def recv_exact(sock, n):
    parts = bytearray()
    while len(parts) < n:
        b = sock.recv(n - len(parts))
        if not b:
            raise ConnectionError("การเชื่อมต่อถูกปิด")
        parts += b
    return bytes(parts)


def run(args):
    import sounddevice as sd

    # 1) หา output device (ข้ามถ้า --no-play)
    idx = None
    if not args.no_play:
        idx = find_output(args.device)
        if idx is None:
            print("ไม่พบอุปกรณ์เสียงที่ต้องการ ลองรัน --list-devices เพื่อดูรายชื่อ แล้วใช้ --device \"<ชื่อ>\"")
            return 1

    # 2) ต่อ iPad ผ่าน usbmux (import ตรงนี้ เพื่อให้ --check/--list-devices ไม่ต้องติดตั้ง pymobiledevice3)
    from pymobiledevice3.usbmux import select_device
    dev = select_device()
    if dev is None:
        print("ไม่พบ iPad — เสียบสาย/ปลดล็อก/กด Trust")
        return 1
    sock = dev.connect(args.port)

    wav = None
    stream = None
    try:
        # 3) อ่านและตรวจ header
        magic, ver, ch, rate, fmt, rsv = struct.unpack(HEADER_FMT, recv_exact(sock, HEADER_SIZE))
        if (magic, ver, ch, rate, fmt) != (b"IPMC", 1, 1, RATE, 1):
            print(f"header ไม่ตรง: magic={magic!r} version={ver} channels={ch} rate={rate} format={fmt}")
            return 1
        log("header ถูกต้อง (IPMC v1, mono, 48000 Hz, Float32)")

        jb = Jitter(args.buffer_ms)

        if args.wav:
            wav = wave.open(args.wav, "wb")
            wav.setnchannels(1)
            wav.setsampwidth(2)  # wave รองรับแค่ PCM integer จึงแปลงเป็น int16
            wav.setframerate(RATE)

        # 4) เปิดลำโพง: 2 channel เพราะ CABLE Input เป็น stereo (mono ผ่าน WASAPI shared อาจล้ม)
        if not args.no_play:
            def cb(outdata, frames, t, status):
                m = jb.pull(frames)
                outdata[:, 0] = m
                outdata[:, 1] = m

            try:
                sd.check_output_settings(device=idx, samplerate=RATE, channels=2, dtype="float32")
            except Exception as e:
                print(f"เปิดอุปกรณ์ไม่ได้ ({e}) — ตั้ง CABLE Input เป็น 48000 Hz ใน Sound Control Panel")
                return 1
            stream = sd.OutputStream(device=idx, samplerate=RATE, channels=2,
                                     dtype="float32", callback=cb)
            stream.start()

        # 5) loop รับ: อ่านเป็นก้อนเต็มขนาด sample (ผลคูณ 4 byte)
        last_log = time.time()
        carry = b""
        sock.settimeout(1.0)
        while True:
            try:
                data = sock.recv(8192)
            except TimeoutError:
                data = None
            except OSError as e:
                if "timed out" in str(e).lower():
                    data = None
                else:
                    raise
            if data is not None:
                if not data:
                    log("iPad ปิดการเชื่อมต่อ")
                    break
                data = carry + data
                keep = len(data) // BYTES_PER_FRAME * BYTES_PER_FRAME
                carry = data[keep:]
                data = data[:keep]
                if wav and data:
                    x = np.frombuffer(data, dtype="<f4")
                    wav.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
                if not args.no_play and data:
                    jb.push(data)
            # 6) log ทุก 10 วินาที
            if time.time() - last_log >= 10:
                last_log = time.time()
                log(f"buffer {jb.level_ms():.0f} ms | สะดุด {jb.underruns} ครั้ง | ล้น {jb.overflows} ครั้ง")
        return 0
    except KeyboardInterrupt:
        print("\nหยุดโดยผู้ใช้")
        return 0
    finally:
        # 9) ปิดทุกอย่างให้เรียบร้อย ไม่งั้นไฟล์ WAV header จะไม่สมบูรณ์
        if stream:
            stream.stop()
            stream.close()
        try:
            sock.close()
        except Exception:
            pass
        if wav:
            wav.close()


def main():
    p = argparse.ArgumentParser(description="รับเสียงจากแอป iPad Mic ผ่าน USB")
    p.add_argument("--port", type=int, default=7777)
    p.add_argument("--device", default=None, help='ชื่ออุปกรณ์เสียงออก (ค่าเริ่มต้น: หา "CABLE Input")')
    p.add_argument("--buffer-ms", type=int, default=30)
    p.add_argument("--wav", help="บันทึกเสียงที่รับลงไฟล์ WAV")
    p.add_argument("--no-play", action="store_true", help="ไม่เปิดลำโพง (ทดสอบอัดอย่างเดียว)")
    p.add_argument("--check", metavar="FILE", help="วิเคราะห์ไฟล์ WAV แล้วจบ")
    p.add_argument("--list-devices", action="store_true", help="แสดงอุปกรณ์เสียงแล้วจบ")
    args = p.parse_args()

    if args.check:
        sys.exit(check_wav(args.check))
    if args.list_devices:
        list_devices()
        sys.exit(0)
    sys.exit(run(args))


if __name__ == "__main__":
    main()
