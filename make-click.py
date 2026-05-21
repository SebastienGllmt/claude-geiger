#!/usr/bin/env python3
"""Synthesize click.wav — a short, sharp geiger-counter tick.

Run once: `python3 make-click.py`. Produces click.wav next to this file.
Tweak DUR / the tone+noise mix below if you want a different timbre.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
DUR = 0.030  # seconds — keep it short so rapid ticks stay crisp
N = int(RATE * DUR)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "click.wav")

random.seed(1)  # deterministic so the committed wav is reproducible
frames = []
for i in range(N):
    t = i / RATE
    env = math.exp(-t * 220.0)            # fast exponential decay -> a "tick"
    tone = math.sin(2 * math.pi * 2200 * t)
    noise = random.uniform(-1.0, 1.0)
    s = env * (0.55 * tone + 0.45 * noise)
    s = max(-1.0, min(1.0, s)) * 0.8       # headroom
    frames.append(struct.pack("<h", int(s * 32767)))

with wave.open(OUT, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(frames))

print("wrote", OUT)
