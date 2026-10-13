#!/usr/bin/env python3
"""Prepare a NEW private runtime from allowlisted public artifacts; never migrate data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP = 'Local Edgeless Type.app'
ASSETS = ('AppIcon.icns', 'start.wav', 'stop.wav', 'soft-start.wav',
          'soft-stop.wav', 'low-start.wav', 'low-stop.wav')


def regular(source, relative):
    path = source / relative
    if any(p.is_symlink() for p in [path, *path.parents] if p != source.parent):
        raise ValueError('Symlinked installation artifacts are not supported')
    if not path.is_file(): raise ValueError('Required build artifact is missing; run bootstrap and pack-app first')
    return path


def model_manifest(source):
    text = regular(source, 'Scripts/bootstrap.sh').read_text()
    models = re.findall(r'^fetch_model (ggml-[A-Za-z0-9.-]+\.bin) ([0-9a-f]{64})(?: .*)?$', text, re.MULTILINE)
    if len(models) != 3 or len({name for name, _ in models}) != 3:
        raise ValueError('Expected the three pinned speech models')
    return models


def prepare(source, target):
    source = source.resolve()
    if target.is_symlink(): raise ValueError('Destination must not be a symlink')
    target = target.resolve()
    if target == source or source in target.parents or target in source.parents:
        raise ValueError('Choose a separate private directory outside the source checkout')
    if target.exists(): raise ValueError('Destination already exists; use the update or migration guide instead')
    if not target.parent.is_dir(): raise ValueError('Choose an existing parent directory')
    models = model_manifest(source)
    files = [('Engine/whisper-server', 'Engine/whisper-server')]
    prefix = 'edgelesstype.app/Contents/'
    for rel in ['MacOS/edgelesstype', 'Info.plist', '_CodeSignature/CodeResources'] + ['Resources/' + asset for asset in ASSETS]:
        files.append((prefix + rel, APP + '/Contents/' + rel))
    files += [('Models/' + name, 'Models/' + name) for name, _ in models]
    paths = [(regular(source, src), dest) for src, dest in files]
    example = regular(source, 'Config/app.example.json')
    config = json.loads(example.read_text())  # Never read Config/app.json or private/.
    for name, expected in models:
        with regular(source, 'Models/' + name).open('rb') as handle:
            if hashlib.file_digest(handle, 'sha256').hexdigest() != expected:
                raise ValueError('Model checksum mismatch; repair bootstrap downloads before continuing')
    for app in [source/'edgelesstype.app', source/'Engine/whisper-server']:
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
    required = sum(path.stat().st_size for path, _ in paths) + 256 * 1024 * 1024
    if shutil.disk_usage(target.parent).free < required:
        raise ValueError('Not enough space for a separate private runtime')
    target.mkdir(mode=0o700)  # Exclusive creation: never overwrite an existing installation.
    try:
        for path, relative in paths:
            dest = target / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
        (target/'Config').mkdir(mode=0o700)
        for dest in [target/'Config/app.json', target/APP/'Contents/Resources/app.json']:
            dest.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n')
        (target/'Config/app.json').chmod(0o600)
    except Exception:
        shutil.rmtree(target)
        raise
    print('Private runtime prepared from public artifacts only. No existing private data was read or copied.')
    print('Do not launch yet. Configure your own signer, run update-local-app.py, then grant permissions to the private app.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', type=Path, required=True)
    args = parser.parse_args()
    prepare(ROOT, args.target)


if __name__ == '__main__':
    try: main()
    except ValueError as error: raise SystemExit(str(error))
    except (OSError, subprocess.CalledProcessError):
        raise SystemExit('Runtime preparation failed. Check build artifacts, signature verification, available space and destination access. No existing installation was overwritten.')
