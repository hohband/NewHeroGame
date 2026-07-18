#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《水浒战棋》占位 BGM 程序合成器（决策日志 D39 注）。

纯标准库 chiptune 作曲：五声音阶（宫商角徵羽）旋律 + 方波主奏（唢呐感）+
三角波贝斯 + 噪声鼓组。三首循环曲，对应 docs/handoff/音频-AI音乐prompt.md 的方向，
正式 BGM 到货后按同名文件替换，AudioManager 接口不变。

用法：python3 tools/synth_bgm.py   # 生成到 assets/audio/bgm/
"""
import math
import os
import struct
import wave

SR = 48000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "bgm")

# A4 = 440，MIDI 号 → 频率
def freq(midi):
    return 440.0 * math.pow(2.0, (midi - 69) / 12.0)

C3, D3, E3, G3, A3 = 48, 50, 52, 55, 57
C4, D4, E4, F4, G4, A4, B4 = 60, 62, 64, 65, 67, 69, 71
C5, D5, E5, G5, A5 = 72, 74, 76, 79, 81


# ---------------------------------------------------------------- 乐器

def play_tone(buf, start, midi, dur, vol=0.3, shape="square", vibrato=0.0, decay=0.0):
    """往 buf 叠一个音：start/dur 秒；vibrato 为频率抖动比例；decay 为尾音衰减（指数）。"""
    n = int(dur * SR)
    f0 = freq(midi)
    off = int(start * SR)
    for i in range(n):
        t = i / SR
        f = f0 * (1.0 + vibrato * math.sin(2 * math.pi * 6.0 * t))
        ph = (i * f / SR) % 1.0
        if shape == "square":
            v = 1.0 if ph < 0.5 else -1.0
        elif shape == "tri":
            v = 4.0 * abs(ph - 0.5) - 1.0
        else:
            v = math.sin(2 * math.pi * ph)
        e = 1.0
        if decay > 0:
            e = math.exp(-t / decay)
        if t < 0.005:
            e *= t / 0.005
        idx = off + i
        if idx < len(buf):
            buf[idx] += v * vol * e


def kick(buf, start, vol=0.5):
    n = int(0.09 * SR)
    off = int(start * SR)
    for i in range(n):
        t = i / SR
        f = 90 * math.exp(-t / 0.03) + 45
        v = math.sin(2 * math.pi * f * t) * math.exp(-t / 0.04)
        if off + i < len(buf):
            buf[off + i] += v * vol


def hat(buf, start, vol=0.12, dur=0.03):
    import random
    n = int(dur * SR)
    off = int(start * SR)
    for i in range(n):
        t = i / SR
        v = random.uniform(-1, 1) * math.exp(-t / (dur / 3))
        if off + i < len(buf):
            buf[off + i] += v * vol


def snare(buf, start, vol=0.3):
    import random
    n = int(0.08 * SR)
    off = int(start * SR)
    last = 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1, 1)
        last = last + 0.4 * (x - last)
        v = last * math.exp(-t / 0.03) + math.sin(2 * math.pi * 180 * t) * 0.4 * math.exp(-t / 0.02)
        if off + i < len(buf):
            buf[off + i] += v * vol


# ---------------------------------------------------------------- 音序器

class Song:
    def __init__(self, bpm, bars):
        self.bpm = bpm
        self.bars = bars
        self.beat = 60.0 / bpm
        self.buf = [0.0] * (int(bars * 4 * self.beat * SR) + SR)

    def at(self, bar, beat):
        return (bar * 4 + beat) * self.beat

    def render(self, path, peak=0.8):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        mx = max(1e-6, max(abs(v) for v in self.buf))
        frames = bytearray()
        for v in self.buf:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v / mx * peak)) * 32767))
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(bytes(frames))
        print(f"  {os.path.basename(path)}  ({len(self.buf)/SR:.1f}s, {self.bars} bars @ {self.bpm}bpm)")


def drums(s, pattern, bars=None):
    """pattern: {beat: 'k'|'h'|'s'|'.'} 每小节 16 步（beat*4 = 16分音符步）。"""
    bars = bars or s.bars
    for bar in range(bars):
        for step, kind in enumerate(pattern):
            t = s.at(bar, step / 4.0)
            if kind == "k":
                kick(s.buf, t)
            elif kind == "h":
                hat(s.buf, t)
            elif kind == "s":
                snare(s.buf, t)
            elif kind == "x":
                kick(s.buf, t)
                hat(s.buf, t)


# ---------------------------------------------------------------- 三首曲子

def bgm_main():
    """《聚义》：110bpm，豪迈市井主题曲（唢呐感方波主奏 + 五度贝斯 + 稳鼓点）。"""
    s = Song(110, 16)
    # 主奏（五声音阶大调，2 小节动机 × 变奏）
    lead = [
        # bar0-1：主题动机
        (0, 0, E4, 1.0), (0, 1, G4, 0.5), (0, 1.5, A4, 0.5), (0, 2, G4, 1.0), (0, 3, E4, 0.5), (0, 3.5, D4, 0.5),
        (1, 0, E4, 0.5), (1, 0.5, G4, 0.5), (1, 1, A4, 0.5), (1, 1.5, C5, 0.5), (1, 2, A4, 1.0), (1, 3, G4, 1.0),
        # bar2-3：上行展开
        (2, 0, E4, 1.0), (2, 1, G4, 0.5), (2, 1.5, A4, 0.5), (2, 2, C5, 1.0), (2, 3, D5, 0.5), (2, 3.5, C5, 0.5),
        (3, 0, A4, 1.5), (3, 1.5, G4, 0.5), (3, 2, A4, 0.5), (3, 2.5, G4, 0.5), (3, 3, E4, 1.0),
        # bar4-5：再现
        (4, 0, E4, 1.0), (4, 1, G4, 0.5), (4, 1.5, A4, 0.5), (4, 2, G4, 1.0), (4, 3, E4, 0.5), (4, 3.5, D4, 0.5),
        (5, 0, E4, 0.5), (5, 0.5, G4, 0.5), (5, 1, A4, 0.5), (5, 1.5, C5, 0.5), (5, 2, A4, 1.0), (5, 3, G4, 1.0),
        # bar6-7：收束回主音（可循环）
        (6, 0, D4, 1.0), (6, 1, E4, 0.5), (6, 1.5, G4, 0.5), (6, 2, E4, 1.0), (6, 3, D4, 1.0),
        (7, 0, C4, 2.0), (7, 2, D4, 1.0), (7, 3, E4, 1.0),
    ]
    for bar in range(2):  # 两遍 8 小节
        for (bar_, beat, note, dur) in lead:
            play_tone(s.buf, s.at(bar * 8 + bar_, beat), note, dur * s.beat * 0.95,
                      vol=0.30, shape="square", vibrato=0.012)
    # 贝斯：根音五度
    bassline = [C3, C3, G3, G3, A3, A3, G3, G3, C3, C3, G3, G3, A3, G3, C3, G3]
    for bar in range(16):
        for half in range(2):
            root = bassline[(bar * 2 + half) % 16]
            play_tone(s.buf, s.at(bar, half * 2), root, 2 * s.beat * 0.9, vol=0.32, shape="tri")
            play_tone(s.buf, s.at(bar, half * 2 + 1), root + 7, s.beat * 0.9, vol=0.22, shape="tri")
    drums(s, ["k", "h", ".", "h", "s", "h", ".", "h", "k", "h", ".", "h", "s", "h", "h", "h"])
    s.render(os.path.join(OUT, "bgm_main.wav"))


def bgm_battle():
    """《替天行道》：120bpm，鼓点驱动 + 问答式短句。"""
    s = Song(120, 16)
    # 主奏：两个短句问答（呼——呼——应）
    phrase_a = [(0, E4, 0.5), (0.5, E4, 0.5), (1, G4, 0.5), (1.5, A4, 1.0), (2.5, G4, 0.5), (3, E4, 1.0)]
    phrase_b = [(0, D4, 0.5), (0.5, D4, 0.5), (1, E4, 0.5), (1.5, G4, 1.0), (2.5, E4, 0.5), (3, D4, 1.0)]
    answer = [(0, E4, 0.5), (0.5, G4, 0.5), (1, A4, 1.0), (2, C5, 0.5), (2.5, A4, 0.5), (3, G4, 1.0)]
    seq_bars = [phrase_a, phrase_a, phrase_b, answer]
    for rep in range(4):
        for bar in range(4):
            for (beat, note, dur) in seq_bars[bar]:
                play_tone(s.buf, s.at(rep * 4 + bar, beat), note, dur * s.beat * 0.9,
                          vol=0.28, shape="square", vibrato=0.008)
    # 贝斯：八分音符驱动
    bass = [C3, C3, C3, C3, A3 - 12, A3 - 12, A3 - 12, A3 - 12, G3 - 12, G3 - 12, G3 - 12, G3 - 12, A3 - 12, A3 - 12, G3 - 12, G3 - 12]
    for bar in range(16):
        for eighth in range(8):
            root = bass[bar] + (12 if eighth in (3, 7) else 0)
            play_tone(s.buf, s.at(bar, eighth * 0.5), root, 0.5 * s.beat * 0.85, vol=0.30, shape="tri")
    drums(s, ["x", ".", "h", ".", "s", ".", "h", ".", "x", ".", "h", ".", "s", ".", "h", "h"])
    s.render(os.path.join(OUT, "bgm_battle.wav"))


def bgm_camp():
    """《大碗酒》：96bpm，板胡/三弦感的弹跳短音（快衰减拨弦）。"""
    s = Song(96, 8)
    melody = [
        (0, 0, C4, 0.5), (0, 1, E4, 0.5), (0, 2, G4, 0.5), (0, 3, A4, 0.5),
        (1, 0, G4, 1.0), (1, 1.5, E4, 0.5), (1, 2, D4, 0.5), (1, 3, E4, 1.0),
        (2, 0, A4, 0.5), (2, 1, G4, 0.5), (2, 2, E4, 0.5), (2, 3, D4, 0.5),
        (3, 0, C4, 1.5), (3, 2, D4, 0.5), (3, 3, E4, 1.0),
        (4, 0, C4, 0.5), (4, 1, E4, 0.5), (4, 2, G4, 0.5), (4, 3, A4, 0.5),
        (5, 0, C5, 1.0), (5, 1.5, A4, 0.5), (5, 2, G4, 0.5), (5, 3, A4, 1.0),
        (6, 0, G4, 0.5), (6, 1, E4, 0.5), (6, 2, D4, 0.5), (6, 3, E4, 0.5),
        (7, 0, C4, 2.5),
    ]
    for (bar, beat, note, dur) in melody:
        play_tone(s.buf, s.at(bar, beat), note, min(dur * s.beat, 0.22), vol=0.30, shape="square", decay=0.09)
    # 贝斯拨弦：根音跳音
    roots = [C3, G3, A3 - 12, G3, C3, A3 - 12, G3, C3]
    for bar in range(8):
        for eighth in range(4):
            play_tone(s.buf, s.at(bar, eighth), roots[bar], 0.18, vol=0.30, shape="tri", decay=0.10)
    drums(s, ["k", ".", ".", "h", "s", ".", ".", "h", "k", ".", ".", "h", "s", ".", "h", "."])
    s.render(os.path.join(OUT, "bgm_camp.wav"))


if __name__ == "__main__":
    print("合成占位 BGM ->", os.path.abspath(OUT))
    bgm_main()
    bgm_battle()
    bgm_camp()
    print("完成。")
