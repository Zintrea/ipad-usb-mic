"""ทดสอบ Jitter (drift compensation) แบบจำลองเวลา ไม่ต้องใช้ iPad/ฮาร์ดแวร์

รัน: windows\.venv\Scripts\python -m unittest windows/test_receiver.py
"""
import os
import random
import sys
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import receiver  # noqa: E402

RATE = receiver.RATE
CHUNK = 480  # 10 ms


def simulate(drift_ppm, seconds, seed=1, freq=1000.0, jitter_ms=3.0):
    """ผู้ส่งเร็วกว่าผู้เล่น drift_ppm, ก้อนมาช้า/เร็วสุ่ม ±jitter_ms, ผู้เล่นดึงทีละ 480 frame"""
    rnd = random.Random(seed)
    jb = receiver.Jitter(30)
    send_dt = CHUNK / (RATE * (1 + drift_ppm / 1e6))
    arrive, prev = [], 0.0
    for k in range(int(seconds / send_dt) + 10):
        t = max(prev, k * send_dt + rnd.uniform(-jitter_ms, jitter_ms) / 1000)
        arrive.append(t)
        prev = t
    n = np.arange(len(arrive) * CHUNK)
    src = (0.5 * np.sin(2 * np.pi * freq * n / RATE)).astype(np.float32)

    out, levels, ppms, nxt, started = [], [], [], 0, None
    pull_dt = CHUNK / RATE
    for i in range(int(seconds / pull_dt)):
        t = i * pull_dt
        while nxt < len(arrive) and arrive[nxt] <= t:
            jb.push(src[nxt * CHUNK:(nxt + 1) * CHUNK])
            nxt += 1
        levels.append(jb.level_ms())
        was_playing = jb.playing
        out.append(jb.pull(CHUNK))
        ppms.append(jb.ppm)
        if jb.playing and not was_playing and started is None:
            started = i
    return jb, np.concatenate(out), np.array(levels), np.array(ppms), started


class DriftTest(unittest.TestCase):
    def check(self, drift):
        jb, out, levels, ppms, started = simulate(drift, 600)
        self.assertIsNotNone(started)
        self.assertEqual(jb.underruns, 0)
        last = slice(-30000, None)  # 5 นาทีสุดท้าย (ppm ในหน้าต่าง 1 นาทีแกว่งตามเฟสของก้อน ต้องเฉลี่ยยาว)
        self.assertAlmostEqual(levels[last].mean(), 30, delta=5)
        self.assertAlmostEqual(ppms[last].mean(), drift, delta=30)

    def test_sender_faster(self):
        self.check(+100)

    def test_sender_slower(self):
        self.check(-100)

    def test_resampler_no_glitch(self):
        jb, out, levels, ppms, started = simulate(100, 60, seed=2)
        y = out[(started + 2000) * CHUNK // CHUNK * CHUNK:]  # ข้าม transient 20 s
        y = y[: len(y) // CHUNK * CHUNK]
        freq = np.argmax(np.abs(np.fft.rfft(y * np.hanning(len(y))))) * RATE / len(y)
        self.assertAlmostEqual(freq, 1000.0, delta=1.0)
        # sine 1 kHz แอมป์ 0.5: ผลต่างอันดับสองสูงสุดตามทฤษฎี ~0.0086, คลิกจะเกินมาก
        self.assertLess(np.abs(np.diff(y, 2)).max(), 0.02)


class MonitorTest(unittest.TestCase):
    APIS = [{"name": "MME", "default_output_device": 0},
            {"name": "Windows WASAPI", "default_output_device": 2}]

    def devs(self, default_name):
        return [{"name": "Speakers", "hostapi": 0, "max_output_channels": 2},
                {"name": "CABLE Input (VB-Audio)", "hostapi": 1, "max_output_channels": 2},
                {"name": default_name, "hostapi": 1, "max_output_channels": 2}]

    def test_pick_default_headphones(self):
        self.assertEqual(receiver.pick_monitor(self.APIS, self.devs("Headphones (USB)")), 2)

    def test_skip_when_default_is_cable(self):
        # อุปกรณ์หลักเป็น CABLE = เล่นซ้อนเข้า Discord ห้ามเล่น
        self.assertIsNone(receiver.pick_monitor(self.APIS, self.devs("CABLE Input (VB-Audio)")))

    def test_no_wasapi_default(self):
        apis = [self.APIS[0], {"name": "Windows WASAPI", "default_output_device": -1}]
        self.assertIsNone(receiver.pick_monitor(apis, self.devs("Headphones")))

    def test_bluetooth_detected_by_handsfree_twin(self):
        devs = self.devs("Headphones (SIBYL X-1035)") + [
            {"name": "Headset (@System32\\drivers\\bthhfenum.sys,#2;%1 Hands-Free%0\n;(SIBYL X-1035))",
             "hostapi": 1, "max_output_channels": 1}]
        self.assertTrue(receiver.is_bluetooth(devs, 2))

    def test_wired_not_bluetooth(self):
        self.assertFalse(receiver.is_bluetooth(self.devs("Headphones (USB Audio)"), 2))

    def test_off_is_silent_but_still_drains(self):
        mon = receiver.Monitor()
        mon.jb.push(np.full(RATE // 10, 0.5, dtype=np.float32))
        before = mon.jb.level_ms()
        self.assertFalse(np.any(mon.fill(480)))
        self.assertLess(mon.jb.level_ms(), before)  # ยังดึงต่อ buffer ไม่ค้างของเก่าไว้รอตอนเปิด
        mon.on = True
        mon.jb.push(np.full(960, 0.5, dtype=np.float32))
        self.assertTrue(np.allclose(mon.fill(480), 0.5))


if __name__ == "__main__":
    unittest.main()
