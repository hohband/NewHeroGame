#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""《水浒战棋》占位 SFX 程序合成器（决策日志 D39）。

纯标准库（wave/math/random/struct），48kHz 16bit 单声道芯片音。
风格定位：retro/chiptune，与当前占位画面气质一致；正式音频外包到货后整体替换，接口不变。

用法：python3 tools/synth_sfx.py   # 生成到 assets/audio/sfx/
"""
import math
import os
import random
import struct
import wave

SR = 48000
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
random.seed(20260718)


# ---------------------------------------------------------------- 基础构件

def _env(i, n, a=0.005, d=0.0, s=1.0, r=0.01):
    """简易包络：a 起音 / d 衰减 / s 保持电平 / r 释音（秒）。"""
    t = i / SR
    total = n / SR
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * (t - a) / d if d > 0 else 1.0
    if t < total - r:
        return s
    return max(0.0, s * (total - t) / r) if r > 0 else s


def tone(freq, dur, shape="square", vol=0.5, env=(0.005, 0.0, 0.7, 0.02), freq2=None):
    """单音：freq→freq2 渐变；shape = square/sine/tri。"""
    n = int(dur * SR)
    out = []
    for i in range(n):
        f = freq if freq2 is None else freq + (freq2 - freq) * i / n
        ph = (i * f / SR) % 1.0
        if shape == "square":
            v = 1.0 if ph < 0.5 else -1.0
        elif shape == "tri":
            v = 4.0 * abs(ph - 0.5) - 1.0
        else:
            v = math.sin(2 * math.pi * ph)
        out.append(v * vol * _env(i, n, *env))
    return out


def noise(dur, vol=0.5, env=(0.002, 0.0, 0.6, 0.02), lp=None, hp=None, seed=None):
    """噪声：可选一阶低通 lp（0..1，越大越闷）/ 高通 hp（0..1，越大越尖）。"""
    rng = random.Random(seed if seed is not None else random.random())
    n = int(dur * SR)
    out, last = [], 0.0
    for i in range(n):
        x = rng.uniform(-1.0, 1.0)
        if lp is not None:
            last = last + lp * (x - last)
            x = last
        if hp is not None:
            last2 = x - last
            last = x
            x = hp * last2
        out.append(x * vol * _env(i, n, *env))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def seq(notes, step, shape="square", vol=0.5, env=(0.005, 0.0, 0.7, 0.02), dur=None):
    """顺序音列：notes=[freq,...]，step 为每音起始间隔。"""
    out = []
    for idx, f in enumerate(notes):
        seg = tone(f, dur if dur else step * 1.2, shape, vol, env)
        start = int(idx * step * SR)
        while len(out) < start:
            out.append(0.0)
        for j, v in enumerate(seg):
            if start + j < len(out):
                out[start + j] += v
            else:
                out.append(v)
    return out


def at(track, offset):
    out = [0.0] * int(offset * SR)
    out.extend(track)
    return out


def write(name, samples, peak=0.95):
    path = os.path.join(OUT, name + ".wav")
    mx = max(1e-6, max(abs(v) for v in samples))
    frames = bytearray()
    for v in samples:
        frames += struct.pack("<h", int(max(-1.0, min(1.0, v / mx * peak)) * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    print(f"  {name}.wav  ({len(samples)/SR:.2f}s)")


# ---------------------------------------------------------------- 逐一合成（编号对齐 docs/handoff/音频-外包规格表.md）

def main():
    os.makedirs(OUT, exist_ok=True)
    print("合成占位 SFX ->", os.path.abspath(OUT))

    # UI
    write("sfx_ui_click", tone(1200, 0.06, "square", 0.4, freq2=900))
    write("sfx_ui_hover", tone(800, 0.03, "sine", 0.25))

    # 移动（3 变体）
    for i, lp in enumerate([0.25, 0.35, 0.45], 1):
        write(f"sfx_move_0{i}", noise(0.05, 0.35, lp=lp))

    # 近战普攻（3 变体：劈砍 = 噪声 + 低频下坠）
    for i, f in enumerate([220, 190, 250], 1):
        write(f"sfx_atk_melee_0{i}", mix(noise(0.10, 0.5, lp=0.6), tone(f, 0.10, "sine", 0.5, freq2=70)))

    # 远程普攻（2 变体：弓弦 + 破空）
    for i, f in enumerate([1800, 1500], 1):
        write(f"sfx_atk_ranged_0{i}", mix(tone(f, 0.06, "sine", 0.35, freq2=f * 0.6),
                                          noise(0.14, 0.3, hp=0.8)))

    # 受击（2 变体）
    for i, f in enumerate([150, 130], 1):
        write(f"sfx_hit_0{i}", mix(noise(0.07, 0.5, lp=0.5), tone(f, 0.08, "sine", 0.5, freq2=60)))

    write("sfx_dodge", noise(0.12, 0.35, hp=0.85))
    write("sfx_block", mix(tone(220, 0.15, "square", 0.4), tone(331, 0.15, "square", 0.3)))
    write("sfx_crit", mix(noise(0.10, 0.5, lp=0.6), tone(800, 0.18, "square", 0.35, freq2=1600)))
    write("sfx_die", mix(tone(300, 0.35, "sine", 0.5, freq2=60), at(noise(0.08, 0.4, lp=0.4), 0.3)))
    write("sfx_heal", seq([523, 659, 784, 1047], 0.09, "sine", 0.35))
    write("sfx_buff", seq([440, 554], 0.08, "square", 0.35))
    write("sfx_debuff", seq([554, 440], 0.08, "square", 0.35))
    write("sfx_turn", seq([880, 1175], 0.09, "square", 0.3))
    write("sfx_win", mix(seq([523, 659, 784, 1047, 1319], 0.12, "square", 0.4),
                         noise(0.05, 0.2, hp=0.9)))
    write("sfx_lose", seq([220, 147], 0.35, "sine", 0.4, dur=0.4))
    write("sfx_levelup", seq([523, 587, 659, 698, 784], 0.07, "square", 0.35))
    write("sfx_unlock", mix(tone(100, 0.10, "sine", 0.6, freq2=50), at(tone(2000, 0.25, "sine", 0.25), 0.08)))
    write("sfx_collect", mix(noise(0.08, 0.4, lp=0.4), at(tone(500, 0.10, "sine", 0.3, freq2=700), 0.06)))

    # 绝技（通用 + 4 个签名）
    write("sfx_ult_generic", mix(noise(0.15, 0.6, lp=0.5), tone(300, 0.6, "square", 0.35, freq2=900)))
    write("sfx_ult_fengxue", mix(noise(1.0, 0.3, lp=0.25), at(noise(0.18, 0.5, hp=0.7), 0.7),
                                   at(tone(900, 0.15, "sine", 0.3, freq2=200), 0.75)))
    write("sfx_ult_chuiyangliu", mix(tone(60, 0.7, "sine", 0.6, freq2=45),
                                       at(mix(noise(0.2, 0.7, lp=0.5), tone(80, 0.25, "sine", 0.6, freq2=40)), 0.65)))
    write("sfx_ult_jiangmenshen", mix(*[at(mix(noise(0.08, 0.5, lp=0.6), tone(200 + k * 60, 0.08, "sine", 0.5, freq2=80)), k * 0.13) for k in range(4)]))
    write("sfx_ult_wulei", mix(noise(0.15, 0.6, hp=0.7), at(noise(0.4, 0.6, lp=0.5), 0.1),
                               at(tone(70, 0.5, "sine", 0.5, freq2=45), 0.15)))

    print("完成。")


if __name__ == "__main__":
    main()
