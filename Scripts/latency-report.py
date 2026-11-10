#!/usr/bin/env python3
"""Summarise Config/latency-history.json: how long each pasted dictation took. Numbers only; no audio or text is stored."""
from pathlib import Path
import json
import statistics
import sys

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / 'Config/latency-history.json'
if not path.is_file():
    sys.exit(f'{path} not found: no dictation has been recorded yet.')
rows = json.loads(path.read_text())
times = sorted(r['timeToPasteReadySeconds'] for r in rows if r.get('timeToPasteReadySeconds', 0) > 0)
if not times:
    sys.exit('No timed dictations yet.')


def at(fraction):
    return times[min(len(times) - 1, int(len(times) * fraction))]


print(f"{len(times)} dictations, {rows[0]['recordedAt']} to {rows[-1]['recordedAt']}")
print(f"median {statistics.median(times):.1f}s  p90 {at(0.9):.1f}s  p99 {at(0.99):.1f}s  slowest {times[-1]:.1f}s")
for limit in (3, 5, 10):
    over = sum(t > limit for t in times)
    print(f"over {limit:>2}s: {over:>4}  ({over / len(times):.0%})")
reasons = {}
for r in rows:
    key = r.get('localReason', 'cloud' if r.get('cloudAttempts') else 'local')
    reasons.setdefault(key, []).append(r.get('timeToPasteReadySeconds', 0))
print('text came from:')
for key, values in sorted(reasons.items(), key=lambda item: -len(item[1])):
    print(f"  {key:<7} {len(values):>4}  median {statistics.median(values):.1f}s")
