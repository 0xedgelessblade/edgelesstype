#!/usr/bin/env python3
"""Summarise Config/latency-history.json: how long each pasted dictation took, per recognition backend.
Numbers only; no audio or text is stored. Records from before the backend label existed are kept and shown as "unlabelled"."""
from pathlib import Path
import json
import statistics
import sys

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'Config/latency-history.json'
if not path.is_file():
    sys.exit(f'{path} not found: no dictation has been recorded yet.')
rows = [r for r in json.loads(path.read_text()) if r.get('timeToPasteReadySeconds', 0) > 0]
if not rows:
    sys.exit('No timed dictations yet.')


def backend(row):
    if row.get('backend'):
        return row['backend']
    # The first live records were written before the label existed; their live timings identify them.
    return 'geminiLive' if 'liveConnectSeconds' in row or 'liveFinalSeconds' in row else 'unlabelled'


def median(values):
    return f'{statistics.median(values):.1f}s' if values else '   -'


def summarise(name, group):
    times = sorted(r['timeToPasteReadySeconds'] for r in group)
    at = lambda fraction: times[min(len(times) - 1, int(len(times) * fraction))]
    print(f"\n{name}: {len(times)} dictations, {group[0]['recordedAt']} to {group[-1]['recordedAt']}")
    print(f"  paste     median {median(times)}  p90 {at(0.9):.1f}s  slowest {times[-1]:.1f}s")
    print(f"  recognise median {median([r['recognitionSeconds'] for r in group if r.get('recognitionSeconds')])}"
          f"   correct median {median([r['correctionSeconds'] for r in group if r.get('correctionSeconds', 0) > 0.05])}")
    by_model = {}
    for r in group:
        if r.get('correctionModel') and r.get('correctionSeconds', 0) > 0.05:
            by_model.setdefault(r['correctionModel'], []).append(r['correctionSeconds'])
    for model, values in by_model.items():
        print(f"  correct   {model}: {len(values)} ({median(values)}, slowest {max(values):.1f}s)")
    live = [r['liveFinalSeconds'] for r in group if r.get('liveFinalSeconds')]
    if live:
        print(f"  live      release to text median {median(live)}  slowest {max(live):.1f}s"
              f"   connect median {median([r['liveConnectSeconds'] for r in group if r.get('liveConnectSeconds')])}")
    print('  over ' + '  '.join(f"{limit}s: {sum(t > limit for t in times)} ({sum(t > limit for t in times) / len(times):.0%})" for limit in (3, 5, 10)))
    sources = {}
    for r in group:
        sources.setdefault(r.get('localReason', 'cloud' if r.get('cloudAttempts') else 'local'), []).append(r['timeToPasteReadySeconds'])
    print('  text from ' + '  '.join(f"{key}: {len(values)} ({median(values)})" for key, values in sorted(sources.items(), key=lambda item: -len(item[1]))))


groups = {}
for row in rows:
    groups.setdefault(backend(row), []).append(row)
print(f"{len(rows)} dictations in {path.name}")
for name, group in groups.items():
    summarise(name, group)
