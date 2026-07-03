#!/usr/bin/env python3
"""Synthesize the geiger tick sounds.

Run once: `python3 sound/make-click.py`. Writes the catalog next to this file in
sound/catalogue/ (one <name>.wav per SOUNDS preset). The DEFAULT sound
(sound/catalogue/classic.wav) doubles as the fallback tick used with no config /
no jq / unknown model.

Each sound gets a distinct character so overlapping ticks stay tellable apart.
Tweak the SOUNDS presets below (shape / freq / noise / decay) and re-run to taste.

What actually separates two short clicks (tested by ear, 30 ms ticks):
  - pitch, noise mix, and decay do most of the work;
  - WAVEFORM barely matters between sine and triangle — the fast exponential
    decay kills the upper harmonics almost immediately, so what's left is the
    attack transient plus noise, which sound nearly identical. Sine and triangle
    at the same pitch are basically indistinguishable here.
  - waveform DOES separate square and saw: their strong odd/all-harmonic content
    survives long enough to read as a buzzy / bright timbre.
So: reach for pitch/noise/decay first; use shape only to get a square-buzz or
saw-bright character, not to distinguish two otherwise-similar smooth ticks.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
DUR = 0.030  # seconds — keep it short so rapid ticks stay crisp
N = int(RATE * DUR)
HERE = os.path.dirname(os.path.abspath(__file__))


def wave_sample(shape, phase):
    """One sample of the given waveform at phase (in cycles, 0..1 repeating)."""
    x = 2 * math.pi * phase
    if shape == "sine":
        return math.sin(x)
    if shape == "square":
        return 1.0 if math.sin(x) >= 0 else -1.0
    if shape == "triangle":
        return (2 / math.pi) * math.asin(math.sin(x))
    if shape == "saw":
        return 2 * (phase - math.floor(phase + 0.5))
    raise ValueError(f"unknown shape: {shape}")


def synth(path, freq, shape="sine", noise=0.45, decay=220.0):
    random.seed(1)  # deterministic so committed wavs are reproducible
    frames = []
    for i in range(N):
        t = i / RATE
        env = math.exp(-t * decay)                 # exponential decay -> a "tick"
        tone = wave_sample(shape, freq * t)
        n = random.uniform(-1.0, 1.0)
        s = env * ((1 - noise) * tone + noise * n)
        s = max(-1.0, min(1.0, s)) * 0.8            # headroom
        frames.append(struct.pack("<h", int(s * 32767)))
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(frames))
    print("wrote", path)


# Baked-in sound catalog — named by CHARACTER, independent of any model tier.
# Which model plays which sound lives in sounds.json, NOT here; these are just
# the palette. Add a preset by adding an entry, then reference its name in the
# JSON. Each writes click-<name>.wav.
SOUNDS = {
    "classic": dict(freq=2200, shape="sine",   noise=0.45, decay=220),  # the original tick
    "boop":    dict(freq=1500, shape="sine",   noise=0.30, decay=180),  # soft, low
    "buzz":    dict(freq=2600, shape="square", noise=0.35, decay=240),  # buzzy
    "bright":  dict(freq=3200, shape="saw",    noise=0.70, decay=300),  # crisp, bright
}
DEFAULT = "classic"  # zero-config / unknown-model fallback

CATALOG = os.path.join(HERE, "catalogue")
os.makedirs(CATALOG, exist_ok=True)
for name, p in SOUNDS.items():
    synth(os.path.join(CATALOG, f"{name}.wav"), **p)
