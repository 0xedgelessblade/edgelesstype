#!/usr/bin/env python3
"""Synthetic filesystem checks for private runtime preservation; no real settings or app."""
import importlib.util
from pathlib import Path
import plistlib
import json
import subprocess
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updater', Path(__file__).with_name('update-local-app.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory); source = root / 'public'; target = root / 'local'
    source_contents = source / 'edgelesstype.app/Contents'
    target_contents = target / 'Local Edgeless Type.app/Contents'
    for contents in (source_contents, target_contents):
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Resources').mkdir()
        (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'edgelessblade.opentypeless'}))
        (contents / 'MacOS/edgelesstype').write_bytes(b'old' if contents == target_contents else b'new')
        for name in ('AppIcon.icns','start.wav','stop.wav','soft-start.wav','soft-stop.wav','low-start.wav','low-stop.wav'):
            (contents / 'Resources' / name).write_bytes(b'public asset')
    preserved = {}
    for name in ('Config/app.json','Config/vocabulary.json','Config/transcription.json','private/store.encrypted.json',
                 'Models/example.bin','Sources/legacy.swift','Local Edgeless Type.app/Contents/Resources/app.json'):
        p = target / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(b'synthetic private sentinel'); preserved[p] = p.read_bytes()
    (target / 'LOCAL-SIGNING.json').write_text(json.dumps({'bundleIdentifier':module.LOCAL_ID,'identitySHA1':'a'*40}))
    dr='identifier \"'+module.LOCAL_ID+'\" and certificate leaf = H\"'+ 'a'*40 +'\"'
    response=subprocess.CompletedProcess([],0,stdout='designated => '+dr+'\n',stderr='')
    with patch.object(module.subprocess, 'run', return_value=response):
        module.install(source, target, 'Local Edgeless Type', 'fixture-revision')
    assert all(p.read_bytes() == value for p, value in preserved.items())
    assert (target_contents / 'MacOS/edgelesstype').read_bytes() == b'new'
    assert plistlib.loads((target_contents / 'Info.plist').read_bytes())['CFBundleDisplayName'] == 'Local Edgeless Type'
    assert not (source / 'private').exists()
    assert not list((target / '.build').rglob('*.app'))
    print('PASS private settings, dictionary, credentials, models, legacy source and bundled config preserved; no reverse sync or duplicate app backup')
    (source_contents / 'MacOS/edgelesstype').write_bytes(b'failed new version')
    with patch.object(module.subprocess, 'run', side_effect=OSError('synthetic signing failure')):
        try: module.install(source, target, 'Local Edgeless Type', 'fixture')
        except OSError: pass
    assert (target_contents / 'MacOS/edgelesstype').read_bytes() == b'new'
    assert all(p.read_bytes() == value for p, value in preserved.items())
    print('PASS failed signing preserves the existing installation')
    # Exercise failure after mutation, not just preflight failure.
    def reject_new_signature(args, **kwargs):
        if '--force' in args: raise OSError('synthetic signing failure')
        return response
    before={str(p.relative_to(target)):p.read_bytes() for p in target_contents.rglob('*') if p.is_file()}
    with patch.object(module.subprocess, 'run', side_effect=reject_new_signature):
        try: module.install(source,target,'Local Edgeless Type','fixture')
        except OSError: pass
        else: raise AssertionError('Signing failure was not rejected')
    after={str(p.relative_to(target)):p.read_bytes() for p in target_contents.rglob('*') if p.is_file()}
    assert before==after
    print('PASS failed signing restores all original signed bytes without ad-hoc re-signing')
    with patch.object(module.subprocess, 'run', return_value=response) as calls:
        module.install(source,target,'Local Edgeless Type','second-build')
        assert any(any(arg.startswith('-R=') for arg in call.args[0]) for call in calls.call_args_list)
        assert all(not ('--sign' in call.args[0] and '-' in call.args[0]) for call in calls.call_args_list)
    print('PASS updates validate the previous certificate-backed identity')
    before=(target_contents/'MacOS/edgelesstype').read_bytes()
    inspected=[0]
    def changed_identity(args, **kwargs):
        if '-d' in args:
            inspected[0]+=1
            if inspected[0]>1:
                return subprocess.CompletedProcess([],0,stdout='',stderr='designated => '+dr.replace('a'*40,'b'*40)+'\n')
        return response
    with patch.object(module.subprocess,'run',side_effect=changed_identity):
        try: module.install(source,target,'Local Edgeless Type','changed-signer')
        except ValueError: pass
        else: raise AssertionError('Changed signer was accepted')
    assert (target_contents/'MacOS/edgelesstype').read_bytes()==before
    print('PASS changed signing requirement rolls back')
    (target/'LOCAL-SIGNING.json').unlink()
    original=(target_contents/'MacOS/edgelesstype').read_bytes()
    try: module.install(source,target,'Local Edgeless Type','fixture')
    except FileNotFoundError: pass
    else: raise AssertionError('Missing signer was not rejected')
    assert (target_contents/'MacOS/edgelesstype').read_bytes()==original
    print('PASS missing signer fails before mutation')
