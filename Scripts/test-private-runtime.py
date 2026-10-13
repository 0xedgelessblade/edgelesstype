#!/usr/bin/env python3
"""Synthetic installation fixtures only; no real model, keychain or private files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('prepare', root/'Scripts/prepare-private-runtime.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as temp:
    base = Path(temp); source = base/'source'; source.mkdir()
    def write(name, data=b'fixture'):
        p=source/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(data)
    write('Config/app.example.json', b'{"polish":{"enabled":false}}')
    write('Config/app.json', b'PRIVATE_FIXTURE_NOT_FOR_COPY')
    write('private/credentials.encrypted.json', b'PRIVATE_FIXTURE_NOT_FOR_COPY')
    write('recording.wav', b'PRIVATE_FIXTURE_NOT_FOR_COPY')
    entries=[]
    for name in ['ggml-small.bin', 'ggml-large-v3-turbo.bin', 'ggml-silero-v5.1.2.bin']:
        write('Models/'+name)
        entries.append('fetch_model '+name+' '+hashlib.sha256(b'fixture').hexdigest())
    write('Scripts/bootstrap.sh', ('\n'.join(entries)+'\n').encode())
    write('Engine/whisper-server')
    for rel in ['MacOS/edgelesstype','Info.plist','_CodeSignature/CodeResources']+['Resources/'+a for a in m.ASSETS]:
        write('edgelesstype.app/Contents/'+rel)
    target=base/'runtime'
    with patch.object(m.subprocess,'run'):
        m.prepare(source,target)
    assert not (target/'private').exists() and not (target/'recording.wav').exists()
    assert json.loads((target/'Config/app.json').read_text()) == {'polish':{'enabled':False}}
    assert (target.stat().st_mode & 0o777)==0o700
    assert (target/'Config/app.json').stat().st_mode & 0o777 == 0o600
    def refused(dest):
        try: m.prepare(source,dest)
        except ValueError: return
        raise AssertionError('expected refusal')
    refused(target); refused(source/'runtime')
    link=base/'link'; link.symlink_to(target); refused(link)
    write('Models/ggml-small.bin',b'bad checksum'); refused(base/'bad')
    assert not (base/'bad').exists()
    write('Models/ggml-small.bin')
    with patch.object(m.subprocess,'run',side_effect=OSError('fixture verification failure')):
        try: m.prepare(source,base/'unsigned')
        except OSError: pass
        else: raise AssertionError('expected signature refusal')
    assert not (base/'unsigned').exists()
    with patch.object(m.subprocess,'run'), patch.object(m.shutil,'copy2',side_effect=OSError('fixture copy failure')):
        try: m.prepare(source,base/'failed')
        except OSError: pass
        else: raise AssertionError('expected copy failure')
    assert not (base/'failed').exists() and target.exists()
print('PASS fresh runtime allowlist, privacy separation, permissions, existing-target/symlink/checksum/signature refusal and failed-copy cleanup')
