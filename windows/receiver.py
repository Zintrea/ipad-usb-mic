"""ตัวรับเสียงจาก iPad: รับผ่าน usbmux ชดเชย drift ต่อใหม่เอง แล้วเล่นเข้า CABLE Input

โปรโตคอล: header 16 byte (little-endian) "IPMC"|ver u16|ch u16|rate u32|fmt u16|rsv u16
ตามด้วย Float32 mono ต่อเนื่อง ดู docs/GUIDE.md
"""
import _thread
import argparse
import asyncio
import datetime
import socket
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
    KP = 2000.0       # ppm ต่อ "สัดส่วน level ที่คลาดจากเป้า" (คลาด 5% -> 100 ppm)
    MAX_PPM = 1000.0  # เพดานการปรับอัตรา (1000 ppm ~ 1.7 cent ไม่ได้ยิน)
    TAU = 1.0         # วินาที: เฉลี่ย level ให้เรียบก่อนคุม

    # shortcut: P controller มี offset คงที่เล็กน้อยตาม drift, เปลี่ยนเป็น PI ถ้า buffer หลุดเป้าตอนรันนาน
    def __init__(self, target_ms):
        self.lock = threading.Lock()  # สอง thread แก้ buffer พร้อมกัน ต้องล็อก
        self.target = int(RATE * target_ms / 1000)  # หน่วย frame
        self.underruns = 0
        self.overflows = 0
        self.reset()

    def reset(self):
        with self.lock:
            self.buf = np.zeros(0, dtype=np.float32)
            self.frac = 0.0       # ตำแหน่งอ่านเศษส่วนใน buf[0]..buf[1]
            self.playing = False  # รอให้เต็มเป้าก่อนค่อยเริ่มเล่น
            self.ema = float(self.target)
            self.ppm = 0.0

    def push(self, x):
        with self.lock:
            self.buf = np.concatenate((self.buf, x))
            if len(self.buf) > self.target * 4:
                # ตัดของเก่าเหลือเท่าเป้า
                self.buf = self.buf[len(self.buf) - self.target:]
                self.overflows += 1

    def pull(self, frames):
        with self.lock:
            if not self.playing:
                if len(self.buf) >= self.target:
                    self.playing = True
                else:
                    return np.zeros(frames, dtype=np.float32)
            level = len(self.buf) - self.frac
            self.ema += (level - self.ema) * min(1.0, frames / RATE / self.TAU)
            self.ppm = float(np.clip(self.KP * (self.ema - self.target) / self.target,
                                     -self.MAX_PPM, self.MAX_PPM))
            r = 1 + self.ppm / 1e6
            idx = self.frac + np.arange(frames) * r
            k = int(np.searchsorted(idx, len(self.buf) - 1, side="right"))  # จำนวนที่มีข้อมูลพอ
            out = np.zeros(frames, dtype=np.float32)
            if k:
                out[:k] = np.interp(idx[:k], np.arange(len(self.buf)), self.buf)
            pos = self.frac + k * r
            used = min(int(pos), len(self.buf))
            self.frac = pos - used
            self.buf = self.buf[used:]
            if k < frames:
                self.underruns += 1
                self.playing = False  # เก็บให้เต็มเป้าใหม่ แทนการสะดุดถี่ ๆ
                self.ema = float(self.target)
            return out

    def level_ms(self):
        with self.lock:
            return (len(self.buf) - self.frac) * 1000 / RATE


def recv_exact(sock, n):
    parts = bytearray()
    while len(parts) < n:
        b = sock.recv(n - len(parts))
        if not b:
            raise ConnectionError("การเชื่อมต่อถูกปิด")
        parts += b
    return bytes(parts)


NO_DATA_S = 3.0  # เงียบเกินนี้ถือว่าสายหลุด/แอปหยุด
CONTROL_PORT = 7778  # localhost เท่านั้น: ตัวรับตัวใหม่ใช้สั่งตัวเก่าให้ปิด
MONITOR_PORT = 7779  # บน iPad: ส่ง 1 byte (0/1) บอกว่าปุ่ม "ฟังเสียงตัวเอง" เปิดอยู่ไหม
MONITOR_MS = 10      # buffer ของหูฟังเล็กกว่า CABLE: สะดุดบ้างได้ แต่ดีเลย์ต่ำ


def pick_monitor(apis, devices):
    """อุปกรณ์เสียงหลัก (WASAPI) ของ Windows ไว้เล่นเสียงตัวเอง; ไม่มี หรือเป็น CABLE = None"""
    for api in apis:
        if "wasapi" in api["name"].lower():
            i = api["default_output_device"]
            if i < 0 or "cable" in devices[i]["name"].lower():
                return None
            return i
    return None


def is_bluetooth(devices, idx):
    """หูฟังบลูทูธมีอุปกรณ์ Hands-Free จาก bthhfenum.sys ที่ชื่อรุ่นเดียวกันอยู่ในรายการ
    shortcut: เทียบจากชื่อรุ่นในวงเล็บสุดท้าย รุ่นที่ไม่มีอุปกรณ์ Hands-Free จะตรวจไม่เจอ"""
    name = devices[idx]["name"]
    if "bluetooth" in name.lower():
        return True
    product = name[name.rfind("(") + 1:].rstrip(")").lower() if "(" in name else ""
    return bool(product) and any("bthhfenum" in d["name"].lower() and product in d["name"].lower()
                                 for d in devices)


class Monitor:
    """เสียงที่ส่งไปหูฟัง: ใช้ Jitter แยก เพราะนาฬิกาของหูฟังกับ CABLE ไม่ตรงกัน"""

    def __init__(self):
        self.jb = Jitter(MONITOR_MS)
        self.on = False  # เขียนจาก thread อ่านพอร์ต 7779 อ่านจาก callback (ค่าเดียว ไม่ต้องล็อก)

    def fill(self, frames):
        m = self.jb.pull(frames)  # ดึงต่อแม้ปิด ไม่งั้นเปิดทีหลังจะได้ยินเสียงเก่าค้าง
        return m if self.on else np.zeros(frames, dtype=np.float32)


def watch_monitor(args, mon, socks):
    """ต่อพอร์ต 7779 ของแอป อ่านสถานะปุ่มจนกว่าจะหลุด แอปเวอร์ชันเก่าไม่มีพอร์ตนี้ = ข้าม"""
    from pymobiledevice3.usbmux import select_device

    async def connect():
        dev = await select_device()
        return None if dev is None else await dev.connect(MONITOR_PORT)

    try:
        sock = asyncio.run(connect())
    except Exception:  # shortcut: ไม่แยกชนิด error ทุกกรณีถือว่าแอปไม่มีพอร์ตนี้
        sock = None
    if sock is None:
        log("แอปไม่มีปุ่มฟังเสียงตัวเอง (เวอร์ชันเก่า) ข้าม")
        return
    sock.setblocking(True)
    socks.append(sock)  # ให้ session ปิดได้ตอนจบ
    try:
        while True:
            b = sock.recv(1)
            if not b:
                break
            on = b[-1] == 1
            if on != mon.on:
                mon.on = on
                log(f"ฟังเสียงตัวเอง: {'เปิด' if on else 'ปิด'}")
    except OSError:
        pass
    finally:
        mon.on = False
        sock.close()


def session(args, jb, wav, mon=None):
    """หนึ่งรอบการเชื่อมต่อ คืน None = ลองใหม่, ตัวเลข = จบโปรแกรมด้วย exit code นั้น"""
    from pymobiledevice3.usbmux import select_device

    # pymobiledevice3 11.x: select_device / connect เป็น async
    async def connect():
        dev = await select_device()
        return None if dev is None else await dev.connect(args.port)

    try:
        sock = asyncio.run(connect())
    except Exception:  # shortcut: ไม่แยกชนิด error (ไม่พบ iPad / แอปยังไม่ START) ทุกกรณีรอแล้วลองใหม่
        return None
    if sock is None:
        return None
    sock.setblocking(True)  # socket จาก asyncio เป็น non-blocking แต่ loop ด้านล่างอ่านแบบ blocking
    mon_socks = []
    try:
        sock.settimeout(1.0)
        magic, ver, ch, rate, fmt, rsv = struct.unpack(HEADER_FMT, recv_exact(sock, HEADER_SIZE))
        if (magic, ver, ch, rate, fmt) != (b"IPMC", 1, 1, RATE, 1):
            print(f"header ไม่ตรง: magic={magic!r} version={ver} channels={ch} rate={rate} format={fmt}"
                  " — แอปบน iPad คนละเวอร์ชันกับตัวรับ ติดตั้งแอปใหม่")
            return 1
        log("header ถูกต้อง (IPMC v1, mono, 48000 Hz, Float32)")
        if mon:
            threading.Thread(target=watch_monitor, args=(args, mon, mon_socks), daemon=True).start()

        last_log = last_data = time.time()
        max_gap = 0.0
        carry = b""
        while True:
            try:
                data = sock.recv(8192)
            except OSError as e:  # socket.timeout เป็นลูกของ OSError
                if "timed out" not in str(e).lower():
                    raise
                data = None
            now = time.time()
            if data is not None:
                if not data:
                    log("iPad ปิดการเชื่อมต่อ")
                    return None
                max_gap = max(max_gap, now - last_data)
                last_data = now
                data = carry + data
                keep = len(data) // BYTES_PER_FRAME * BYTES_PER_FRAME
                carry = data[keep:]
                x = np.frombuffer(data[:keep], dtype="<f4")
                if wav and len(x):
                    wav.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
                if not args.no_play and len(x):
                    jb.push(x)
                    if mon:
                        mon.jb.push(x)
            elif now - last_data > NO_DATA_S:
                log(f"ไม่มีข้อมูลเกิน {NO_DATA_S:.0f} วินาที")
                return None
            if now - last_log >= 10:
                last_log = now
                log(f"buffer {jb.level_ms():.0f} ms | สะดุด {jb.underruns} | ล้น {jb.overflows}"
                    f" | drift {jb.ppm:+.0f} ppm | ก้อนใหญ่สุด {max_gap * 1000:.0f} ms")
                max_gap = 0.0
    except OSError as e:  # รวม ConnectionError ตอนอ่าน header และสายหลุดกลางทาง
        log(f"การเชื่อมต่อหลุด ({e})")
        return None
    finally:
        for s in mon_socks:  # ให้ thread อ่านพอร์ต 7779 จบไปพร้อม session
            s.close()
        sock.close()


def take_over():
    """สั่งตัวรับตัวเก่า (ถ้ามี) ให้ปิด แล้วเปิดพอร์ตควบคุมรอให้ตัวถัดไปสั่งปิดเรา
    แอป iPad รับคอมได้ทีละตัว ถ้าเปิดสองตัวจะแย่งกันต่อสลับไปมา"""
    try:
        socket.create_connection(("127.0.0.1", CONTROL_PORT), timeout=1).close()
        log("ปิดตัวรับตัวเก่า")
    except OSError:
        pass
    srv = socket.socket()
    for _ in range(50):  # รอตัวเก่าปล่อยพอร์ต สูงสุด 5 วินาที
        try:
            srv.bind(("127.0.0.1", CONTROL_PORT))
            break
        except OSError:
            time.sleep(0.1)
    else:
        raise SystemExit("ปิดตัวรับตัวเก่าไม่ได้ — ปิดหน้าต่างเก่าเองแล้วเปิดใหม่")
    srv.listen(1)

    def wait():
        srv.accept()
        log("มีตัวรับตัวใหม่เปิดขึ้น ปิดตัวนี้")
        _thread.interrupt_main()  # ให้ main จบผ่าน KeyboardInterrupt ไฟล์ WAV จะปิดครบ

    threading.Thread(target=wait, daemon=True).start()


def open_monitor(sd):
    """เปิดหูฟังไว้เล่นเงียบรอ (กดปุ่มในแอปแล้วได้ยินทันที) เปิดไม่ได้ = ไม่มีฟังเสียงตัวเอง แต่ CABLE ยังทำงาน"""
    devices = sd.query_devices()
    idx = pick_monitor(sd.query_hostapis(), devices)
    if idx is None:
        log("ไม่พบหูฟัง/ลำโพงหลักที่ไม่ใช่ CABLE ปุ่มฟังเสียงตัวเองจะไม่มีเสียง")
        return None, None
    if is_bluetooth(devices, idx):
        log("เตือน: หูฟังนี้เป็นบลูทูธ ดีเลย์ 100+ ms ฟังเสียงตัวเองจะช้าและเหมือนมีเสียงสะท้อน ใช้หูฟังสายจะเรียลไทม์กว่า")
    mon = Monitor()

    def cb(outdata, frames, t, status):
        m = mon.fill(frames)
        outdata[:, 0] = m
        outdata[:, 1] = m

    try:
        # auto_convert: หูฟังบางตัวตั้ง 44.1 kHz ให้ Windows แปลงให้แทนการเปิดไม่ได้
        s = sd.OutputStream(device=idx, samplerate=RATE, channels=2, dtype="float32", callback=cb,
                            latency="low", extra_settings=sd.WasapiSettings(auto_convert=True))
        s.start()
    except Exception as e:
        log(f"เปิดอุปกรณ์ฟังเสียงตัวเองไม่ได้ ({e}) ข้าม")
        return None, None
    log(f"ฟังเสียงตัวเองผ่าน: {sd.query_devices(idx)['name']} (เปิด/ปิดที่ปุ่มในแอป)")
    return mon, s


def run(args):
    import sounddevice as sd

    take_over()

    idx = None
    if not args.no_play:
        idx = find_output(args.device)
        if idx is None:
            print("ไม่พบอุปกรณ์เสียงที่ต้องการ ลองรัน --list-devices เพื่อดูรายชื่อ แล้วใช้ --device \"<ชื่อ>\"")
            return 1

    jb = Jitter(args.buffer_ms)
    wav = stream = mon = mon_stream = None
    try:
        if args.wav:
            wav = wave.open(args.wav, "wb")
            wav.setnchannels(1)
            wav.setsampwidth(2)  # wave รองรับแค่ PCM integer จึงแปลงเป็น int16
            wav.setframerate(RATE)

        # เปิดลำโพงครั้งเดียว 2 channel เพราะ CABLE Input เป็น stereo (mono ผ่าน WASAPI shared อาจล้ม)
        # ระหว่างรอ iPad ลำโพงเล่นเงียบ DAW ไม่ต้องเลือกอุปกรณ์ใหม่
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
                                     dtype="float32", callback=cb, latency="low")
            stream.start()
            mon, mon_stream = open_monitor(sd)

        while True:
            code = session(args, jb, wav, mon)
            if code is not None:
                return code
            log("รอ iPad...")
            jb.reset()
            if mon:
                mon.jb.reset()
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nหยุดโดยผู้ใช้")
        return 0
    finally:
        # ปิดให้เรียบร้อย ไม่งั้น header ของไฟล์ WAV จะไม่สมบูรณ์
        for s in (stream, mon_stream):
            if s:
                s.stop()
                s.close()
        if wav:
            wav.close()


def main():
    # stdout ที่ถูก redirect (Tee-Object, ไฟล์) ใช้ cp1252 แล้วข้อความไทยจะ crash
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
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
