#!/usr/bin/env python3
"""Render the existing Wake synthesizer recipes to offline iOS-compatible PCM WAV."""
import json
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "ios/LunkAlarm/Resources/Sounds"
OUTPUT.mkdir(parents=True, exist_ok=True)
RATE = 44100

for tone in json.loads((ROOT / "src/Wake.Core/tones.json").read_text()):
    samples = []
    for index in range(int(tone["cycle"] * RATE)):
        time = index / RATE
        sample = 0.0
        for note in tone["notes"]:
            pitch, offset, length = note[:3]
            t = time - offset
            if t < 0 or t >= length:
                continue
            phase = pitch * t + ((note[3] - pitch) * t * t / (2 * length) if len(note) > 3 else 0)
            angle = 2 * math.pi * phase
            signal = {
                "square": lambda: 1 if math.sin(angle) >= 0 else -1,
                "triangle": lambda: 2 / math.pi * math.asin(math.sin(angle)),
                "sawtooth": lambda: 2 * (phase - math.floor(phase + 0.5)),
            }.get(tone["wave"], lambda: math.sin(angle))()
            envelope = min(1, t / 0.01) * (
                math.exp(-7 * t / length) if tone["style"] == "ring" else min(1, (length - t) / 0.02)
            )
            sample += signal * tone["volume"] * envelope
        samples.append(int(max(-1, min(1, sample)) * 32767))
    with wave.open(str(OUTPUT / (tone["id"] + ".wav")), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(struct.pack("<" + "h" * len(samples), *samples))
    print(tone["id"], len(samples), "frames")
