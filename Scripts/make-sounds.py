#!/usr/bin/env python3
"""Original soft two-tone cues; deterministic and free of external samples."""
from pathlib import Path
import math
import struct
import wave

root = Path(__file__).resolve().parent.parent
rate = 44100
# Default: the user-approved refined audition, unchanged at the sample level.
for name, freq, duration in [('start', 440.0, .255), ('stop', 349.228, .295)]:
    values = []
    for i in range(round(rate*duration)):
        t = i/rate
        attack = .5-.5*math.cos(math.pi*min(1,t/.025))
        release = .5-.5*math.cos(math.pi*min(1,(duration-t)/.085))
        envelope = attack*release*math.exp(-t/.115)
        values.append(envelope*(math.sin(2*math.pi*freq*t)+.065*math.exp(-t/.060)*math.sin(2*math.pi*2*freq*t)+.018*math.exp(-t/.035)*math.sin(2*math.pi*3*freq*t)))
    gain = .085/max(abs(x) for x in values)
    samples = [round(x*gain*32767) for x in values]
    samples[0] = samples[-1] = 0
    with wave.open(str(root/'Resources'/f'{name}.wav'),'wb') as wav:
        wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(rate)
        wav.writeframes(struct.pack('<'+'h'*len(samples),*samples))
    print(f'{name}: refined default, duration={duration}s')

# B/C are the exact auditioned presets. Normalization matches the previews.
def normalize_cue(values):
    mean = sum(values)/len(values)
    values = [x-mean for x in values]
    fade = min(90,len(values)//10)
    for i in range(fade):
        values[i] *= i/fade
        values[-i-1] *= i/fade
    energy = math.sqrt(sum(x*x for x in values)/rate)
    gain = min(.022/max(energy,1e-12), .32/max(max(abs(x) for x in values),1e-12))
    return [round(max(-1,min(1,x*gain))*32767) for x in values]

for preset in ['soft','low']:
    for name in ['start','stop']:
        stop = name == 'stop'
        duration = .245 if preset == 'soft' else .18
        values = []
        for i in range(int(duration*rate)):
            t = i/rate
            if preset == 'soft':
                freqs = (440,349.23) if stop else (440,587.33)
                value = 0
                for k,freq in enumerate(freqs):
                    q = t-k*.09
                    if q>=0:
                        value += (1-math.exp(-q/.012))*math.exp(-q/.050)*math.sin(2*math.pi*freq*q)
                value *= min(1,(duration-t)/.035)
            else:
                freq = 146.83 if stop else 185
                envelope = (1-math.exp(-t/.005))*math.exp(-t/.040)*min(1,(duration-t)/.04)
                value = envelope*(math.sin(2*math.pi*freq*t)+.14*math.sin(2*math.pi*2*freq*t))
            values.append(value)
        samples = normalize_cue(values)
        with wave.open(str(root/'Resources'/f'{preset}-{name}.wav'),'wb') as wav:
            wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(rate)
            wav.writeframes(struct.pack('<'+'h'*len(samples),*samples))
        print(f'{preset}-{name}: duration={duration}s')
