#!/usr/bin/env python3
"""Synthetic filesystem checks for private runtime preservation; no real settings or app."""
import importlib.util
from pathlib import Path
import plistlib
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updater', Path(__file__).with_name('update-local-app.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory); source = root / 'public'; target = root / 'local'
    source_contents = source / 'edgelesstype.app/Contents'
    target_contents = target / 'Local edgeless Type.app/Contents'
    for contents in (source_contents, target_contents):
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Resources').mkdir()
        (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'edgelessblade.opentypeless'}))
        (contents / 'MacOS/edgelesstype').write_bytes(b'old' if contents == target_contents else b'new')
        for name in ('AppIcon.icns','start.wav','stop.wav','soft-start.wav','soft-stop.wav','low-start.wav','low-stop.wav'):
            (contents / 'Resources' / name).write_bytes(b'public asset')
    preserved = {}
    for name in ('Config/app.json','Config/vocabulary.json','Config/transcription.json','private/store.encrypted.json',
                 'Models/example.bin','Sources/legacy.swift','Local edgeless Type.app/Contents/Resources/app.json'):
        p = target / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(b'synthetic private sentinel'); preserved[p] = p.read_bytes()
    with patch.object(module.subprocess, 'run'):
        module.install(source, target, 'Local edgeless Type', 'fixture-revision')
    assert all(p.read_bytes() == value for p, value in preserved.items())
    assert (target_contents / 'MacOS/edgelesstype').read_bytes() == b'new'
    assert plistlib.loads((target_contents / 'Info.plist').read_bytes())['CFBundleDisplayName'] == 'Local edgeless Type'
    assert not (source / 'private').exists()
    assert not list((target / '.build').rglob('*.app'))
    print('PASS private settings, dictionary, credentials, models, legacy source and bundled config preserved; no reverse sync or duplicate app backup')
    (source_contents / 'MacOS/edgelesstype').write_bytes(b'failed new version')
    with patch.object(module.subprocess, 'run', side_effect=OSError('synthetic signing failure')):
        try: module.install(source, target, 'Local edgeless Type', 'fixture')
        except OSError: pass
    assert (target_contents / 'MacOS/edgelesstype').read_bytes() == b'new'
    assert all(p.read_bytes() == value for p, value in preserved.items())
    print('PASS failed signing restores executable and preserves private files')
