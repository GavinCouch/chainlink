"""Synthesize the original Chainlink loop and message chime (no downloaded samples)."""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
ROOT.mkdir(parents=True, exist_ok=True)
random.seed(7)

def write(name, samples):
    with wave.open(str(ROOT / name), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x)) * 28000)) for x in samples))

def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)

beat = 60 / 80
bar = beat * 4
chords = [(48, 55, 59, 62, 64), (45, 52, 55, 59, 60), (41, 48, 52, 55, 57), (43, 50, 53, 57, 59)]
samples = []
for i in range(int(RATE * bar * 8)):
    t = i / RATE
    pos = t % bar
    chord = chords[int(t / bar) % 4]
    envelope = min(1, pos / .035) * math.exp(-pos * .6) * min(1, (bar - pos) / .08)
    keys = sum((math.sin(2 * math.pi * hz(n) * t) + .18 * math.sin(4 * math.pi * hz(n) * t)) for n in chord[1:]) * .045 * envelope
    bass = math.sin(2 * math.pi * hz(chord[0] - 12) * t) * .13 * envelope
    b = t % beat
    kick = .18 * math.sin(2 * math.pi * (48 * b + 5 * (1 - math.exp(-b * 30)))) * math.exp(-b * 20) if int(t / beat) % 2 == 0 else 0
    hat = random.uniform(-1, 1) * .028 * math.exp(-(t % (beat / 2)) * 100)
    snare = random.uniform(-1, 1) * .06 * math.exp(-b * 28) if int(t / beat) % 4 in (1, 3) else 0
    fade = min(1, t / .03, (bar * 8 - t) / .03)
    samples.append((keys + bass + kick + hat + snare) * fade)
write('quiet_hours.wav', samples)
write('message.wav', [(math.sin(2 * math.pi * 660 * (i / RATE)) + .3 * math.sin(2 * math.pi * 990 * (i / RATE))) * .22 * math.exp(-(i / RATE) * 14) * min(1, i / (RATE * .01)) for i in range(int(RATE * .4))])
print('Generated original 24-second lo-fi loop and message chime.')
