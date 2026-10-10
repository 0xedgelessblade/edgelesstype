#!/usr/bin/env python3
"""Local synthetic-audio checks. No microphone, private settings or cloud API.
Run after bootstrap.sh and pack-app.sh; macOS speech voices create the fixtures.
"""
from pathlib import Path
import argparse
import json
import math
import random
import shutil
import struct
import subprocess
import tempfile
import wave

root = Path(__file__).resolve().parent.parent

def wav(path, samples):
    with wave.open(str(path), 'wb') as stream:
        stream.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
        stream.writeframes(struct.pack('<' + 'h' * len(samples), *[max(-32768, min(32767, round(x))) for x in samples]))

def samples(path):
    with wave.open(str(path)) as stream:
        assert (stream.getnchannels(), stream.getsampwidth(), stream.getframerate()) == (1, 2, 16000)
        data = stream.readframes(stream.getnframes())
    return struct.unpack('<' + 'h' * (len(data) // 2), data)

def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', choices=['small', 'turbo', 'both'], default='both')
    parser.add_argument('--ui', action='store_true', help='Also check no-speech panel dismissal and unchanged clipboard version; never reads clipboard text.')
    parser.add_argument('--app', type=Path, help='Optional signed app for explicit local speaker tests.')
    parser.add_argument('--speaker', action='store_true', help='Explicitly record the microphone for three seconds per cue. Stay silent. Temporary audio is deleted; no transcripts are printed.')
    args = parser.parse_args()
    source_app = args.app or root / 'edgelesstype.app'
    if not source_app.is_dir() or not shutil.which('ffmpeg') or not shutil.which('say'):
        print('FAIL prerequisites: build the app and install FFmpeg on an M-series Mac.'); return 2
    selected = ['small', 'turbo'] if args.model == 'both' else [args.model]
    with tempfile.TemporaryDirectory(prefix='edgelesstype-speech-check-') as directory:
        tmp = Path(directory)
        shutil.copytree(source_app, tmp / 'edgelesstype.app')
        app = tmp / 'edgelesstype.app/Contents/MacOS/edgelesstype'
        (tmp / 'Config').mkdir()
        config = json.loads((root / 'Config/app.example.json').read_text())
        for name in ['serverPath', 'smallModelPath', 'turboModelPath', 'vadModelPath']:
            config['residentSpeech'][name] = str(root / config['residentSpeech'][name])
        rng = random.Random(2026)
        noise = [rng.gauss(0, 60) for _ in range(48000)]
        fixtures = [('digital-silence', [0] * len(noise)), ('room-noise', noise),
                    ('fan-hum', [x + 300 * math.sin(2 * math.pi * 60 * i / 16000) for i, x in enumerate(noise)])]
        clicks = list(noise)
        for at in [4000, 14000, 30000]:
            for i in range(120): clicks[at + i] += rng.gauss(0, 3500) * math.exp(-i / 24)
        fixtures.append(('keyboard-clicks', clicks))
        cases = []
        for name, data in fixtures:
            path = tmp / (name + '.wav'); wav(path, data); cases.append((name, path, False))
        voices = subprocess.check_output(['say', '-v', '?'], text=True)
        candidates = [line.split('zh_TW')[0].strip() for line in voices.splitlines() if 'zh_TW' in line]
        if not candidates:
            print('FAIL speech fixtures: a local Traditional Chinese voice is required.'); return 2
        voice = candidates[0]
        for name, phrase in [('spoken-thanks', '謝謝'), ('spoken-short', '好'), ('spoken-mixed', '請幫我 check the settings 然後重新啟動')]:
            aiff = tmp / (name + '.aiff'); path = tmp / (name + '.wav')
            subprocess.run(['say', '-v', voice, '-o', str(aiff), phrase], check=True, capture_output=True)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(aiff), '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', str(path)], check=True, capture_output=True)
            cases.append((name, path, True))
            if name == 'spoken-mixed':
                quiet = tmp / 'quiet-mixed.wav'; wav(quiet, [x * .06 for x in samples(path)])
                cases.append(('quiet-mixed', quiet, True))
        # Fixed early-speech regressions overlap a known first word with each
        # cue. This verifies capture/ASR, not the hardware echo canceller.
        english = [line.split('en_US')[0].strip() for line in voices.splitlines() if 'en_US' in line]
        if not english:
            print('FAIL speech fixtures: a local English voice is required.'); return 2
        english_voice = 'Samantha' if 'Samantha' in english else english[0]
        aiff = tmp / 'early-speech.aiff'; speech_path = tmp / 'early-speech.wav'
        subprocess.run(['say', '-v', english_voice, '-o', str(aiff), 'Please check the settings.'], check=True, capture_output=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(aiff), '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', str(speech_path)], check=True, capture_output=True)
        speech = list(samples(speech_path))
        onset = next((i for i, x in enumerate(speech) if abs(x) > 150), 0)
        speech = speech[max(0, onset - 160):]
        for preset in ['standard', 'soft', 'low']:
            resource = 'start.wav' if preset == 'standard' else preset + '-start.wav'
            cue = tmp / (preset + '-cue.wav')
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(root / 'Resources' / resource), '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', str(cue)], check=True, capture_output=True)
            tone = samples(cue)
            for delay in [0, 800]:
                data = [0] * 800 + speech + [0] * 8000
                for i, x in enumerate(tone): data[800 + delay + i] += x
                name = f'early-word-{preset}-{delay}'
                path = tmp / (name + '.wav'); wav(path, data)
                cases.append((name, path, True))
        # Exercise the exact native recorder sink, in 512-frame chunks. Check
        # first/last impulses as well as ASR, so a missing prefix cannot hide
        # behind an ASR model guessing the sentence from its remaining words.
        failures = 0
        for rate in [16000, 44100, 48000]:
            impulse = tmp / f'impulse-{rate}.wav'
            values = [0] * rate
            values[0] = 16000; values[-1] = 16000
            with wave.open(str(impulse), 'wb') as stream:
                stream.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
                stream.writeframes(struct.pack('<' + 'h' * len(values), *values))
            converted = tmp / f'converted-{rate}.wav'
            result = subprocess.run([str(app), 'capture-fixture', str(impulse), str(converted)], capture_output=True, timeout=20)
            data = samples(converted) if result.returncode == 0 else []
            passed = abs(len(data) - 16000) <= 2 and any(abs(x) > 100 for x in data[:32]) and any(abs(x) > 100 for x in data[-32:])
            failures += not passed
            print(f'{"PASS" if passed else "FAIL"} native-capture-first-and-last-samples-{rate}', flush=True)
        converted_cases = []
        for name, path, speech in cases:
            converted = tmp / ('captured-' + path.name)
            subprocess.run([str(app), 'capture-fixture', str(path), str(converted)], check=True, capture_output=True, timeout=20)
            converted_cases.append((name, converted, speech))
        cases = converted_cases
        for model in selected:
            config['residentSpeech']['selectedModel'] = model
            (tmp / 'Config/app.json').write_text(json.dumps(config))
            for name, path, expected_speech in cases:
                result = subprocess.run([str(app), 'transcribe', str(path)], capture_output=True, text=True, timeout=110)
                text = result.stdout.strip()
                passed = result.returncode == 0 and (bool(text) if expected_speech else not text)
                if name == 'spoken-thanks': passed = passed and ('謝謝' in text or '谢谢' in text)
                if name.startswith('early-word-'): passed = passed and text.lower().startswith('please')
                failures += not passed
                print(f'{"PASS" if passed else "FAIL"} {model} {name}', flush=True)
            if args.speaker:
                print(f'TEST {model}: three cues in one process; stay silent.', flush=True)
                result = subprocess.run([str(app), 'cue-cycle-probe'], capture_output=True, text=True, timeout=150)
                passed = result.returncode == 0 and result.stdout.count('first-buffer-before-cue=true') == 3 and result.stdout.count('empty=true cloudRequests=0') == 3 and 'cue-cycle-probe-passed=true' in result.stdout
                failures += not passed
                print(f'{"PASS" if passed else "FAIL"} {model} three-speaker-cycles', flush=True)
            if args.ui:
                result = subprocess.run([str(app), 'no-speech-probe', str(tmp / 'room-noise.wav')], capture_output=True, text=True, timeout=110)
                passed = result.returncode == 0 and 'clipboardUnchanged=true' in result.stdout and 'cloudRequests=0' in result.stdout
                failures += not passed
                print(f'{"PASS" if passed else "FAIL"} {model} panel-and-clipboard', flush=True)
        # All generated audio, local fixture configuration and temporary app files
        # disappear when this context exits. Never print a transcript or raw log.
        print(f'Local speech checks: {failures} failures; cloud API never used; microphone={args.speaker}.')
        return 1 if failures else 0

if __name__ == '__main__':
    try: raise SystemExit(run())
    except (OSError, subprocess.SubprocessError, ValueError, KeyError):
        print('FAIL local speech check setup or process; no private logs were emitted.')
        raise SystemExit(2)
