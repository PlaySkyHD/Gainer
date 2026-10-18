#!/usr/bin/env python3
"""Erzeugt die Timertöne als WAV (16 Bit, 44,1 kHz, mono) unter assets/sounds/.

Nur Standardbibliothek, deterministisch: gleicher Aufruf, gleiche Dateien.
Aufruf: python3 tool/generate_timer_sounds.py
"""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
PEAK = 0.8
FADE = 0.004  # Sekunden Ein- und Ausblenden gegen Knackser


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def tone(freq, seconds, partials=((1.0, 1.0),), decay=None, attack=0.003):
    """Sinus mit optionalen Partials (Faktor, Pegel) und exponentiellem Ausklang."""
    count = int(RATE * seconds)
    out = []
    for i in range(count):
        t = i / RATE
        value = sum(
            level * math.sin(2 * math.pi * freq * factor * t)
            for factor, level in partials
        )
        env = min(1.0, t / attack) if attack else 1.0
        if decay:
            env *= math.exp(-t * decay)
        out.append(value * env)
    return out


def mix(*tracks):
    length = max(len(t) for t in tracks)
    out = [0.0] * length
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    return out


def at(offset, track, total):
    """Setzt [track] ab [offset] Sekunden in eine Spur der Länge [total]."""
    out = silence(total)
    start = int(RATE * offset)
    for i, v in enumerate(track):
        if start + i < len(out):
            out[start + i] += v
    return out


def finish(samples):
    peak = max(abs(v) for v in samples) or 1.0
    gain = PEAK / peak
    fade = int(RATE * FADE)
    n = len(samples)
    out = []
    for i, v in enumerate(samples):
        g = gain
        if i < fade:
            g *= i / fade
        if i >= n - fade:
            g *= (n - 1 - i) / fade
        out.append(int(max(-1.0, min(1.0, v * g)) * 32767))
    return out


def digital_alarm():
    beep = tone(2000, 0.09, attack=0.005)
    total = 1.2
    parts = []
    for group in (0.0, 0.5):
        parts.append(at(group, beep, total))
        parts.append(at(group + 0.16, beep, total))
    return mix(*parts)


def boxing_bell():
    ratios = ((1.0, 1.0), (2.76, 0.6), (5.40, 0.4), (8.93, 0.25))
    strike = tone(620, 2.6, ratios, decay=2.2, attack=0.001)
    return mix(strike, at(0.35, tone(620, 2.25, ratios, decay=2.2, attack=0.001), 2.6))


def radar():
    total = 2.4

    def ping(freq):
        return tone(freq, 0.7, decay=6.0, attack=0.004)

    return mix(
        at(0.0, ping(880), total),
        at(0.6, ping(1100), total),
        at(1.2, ping(1320), total),
    )


def bike_bell():
    partials = ((1.0, 1.0), (2.4, 0.5), (4.2, 0.3))
    ring = tone(2600, 0.7, partials, decay=7.0, attack=0.001)
    total = 1.6
    return mix(at(0.0, ring, total), at(0.45, ring, total))


def gong():
    total = 3.0
    a = tone(110, total, ((1.0, 1.0), (2.0, 0.5), (3.01, 0.3), (4.2, 0.2)), decay=1.3)
    b = tone(113, total, ((1.0, 0.8), (2.0, 0.4)), decay=1.3)
    return mix(a, b)


def chime():
    total = 2.4

    def note(freq):
        return tone(freq, 1.2, ((1.0, 1.0), (2.0, 0.25)), decay=3.0, attack=0.004)

    return mix(
        at(0.0, note(523.25), total),
        at(0.28, note(659.25), total),
        at(0.56, note(783.99), total),
    )


def pulse():
    total = 1.8
    return mix(*(at(i * 0.5, tone(440, 0.35, decay=4.0, attack=0.05), total) for i in range(3)))


SOUNDS = {
    "digital_alarm": digital_alarm,
    "boxing_bell": boxing_bell,
    "radar": radar,
    "bike_bell": bike_bell,
    "gong": gong,
    "chime": chime,
    "pulse": pulse,
}


def write(path, samples):
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(b"".join(struct.pack("<h", s) for s in samples))


def main():
    target = Path(__file__).resolve().parent.parent / "assets" / "sounds"
    target.mkdir(parents=True, exist_ok=True)
    for name, build in SOUNDS.items():
        samples = finish(build())
        assert len(samples) <= 3 * RATE, name
        write(target / f"{name}.wav", samples)


if __name__ == "__main__":
    main()
