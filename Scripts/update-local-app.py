#!/usr/bin/env python3
"""Install reviewed app code into an existing private runtime; never sync private data back."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def install(source, target, name, revision):
    if not name or name in ('.', '..') or '/' in name or '\\' in name:
        raise ValueError('Invalid local app name')
    if source.resolve() == target.resolve() or source.resolve() in target.resolve().parents:
        raise ValueError('Choose a separate private runtime directory')
    if not (target / 'Config/app.json').is_file():
        raise ValueError('Target must be an existing configured local installation')
    app = target / (name + '.app')
    executable = app / 'Contents/MacOS/edgelesstype'
    info = app / 'Contents/Info.plist'
    if not executable.is_file() or not info.is_file():
        raise ValueError('Existing local app not found; rename it before updating')
    for entry in (app, app / 'Contents', app / 'Contents/MacOS', app / 'Contents/Resources', executable, info):
        if entry.is_symlink():
            raise ValueError('Local app paths must not be symlinks')
    backup_parent = target / '.build/local-update-backups'
    backup_parent.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='code-', dir=backup_parent))
    # Only executable/metadata backups, not another launchable .app or private data.
    shutil.copy2(executable, backup / 'executable')
    shutil.copy2(info, backup / 'Info.plist')
    payload = source / 'edgelesstype.app/Contents'
    staging = executable.with_name('.edgelesstype-update')
    if staging.exists() or staging.is_symlink():
        raise ValueError('Staging executable already exists')
    try:
        shutil.copy2(payload / 'MacOS/edgelesstype', staging)
        os.replace(staging, executable)
        metadata = plistlib.loads((payload / 'Info.plist').read_bytes())
        metadata['CFBundleName'] = name
        metadata['CFBundleDisplayName'] = name
        info.write_bytes(plistlib.dumps(metadata))
        # Fixed public assets only. In particular, never copy Resources/app.json.
        resources = app / 'Contents/Resources'
        for filename in ('AppIcon.icns', 'start.wav', 'stop.wav', 'soft-start.wav',
                         'soft-stop.wav', 'low-start.wav', 'low-stop.wav'):
            item = payload / 'Resources' / filename
            destination = resources / filename
            if item.is_symlink() or destination.is_symlink():
                raise ValueError('Asset paths must not be symlinks')
            shutil.copy2(item, destination)
        subprocess.run(['codesign', '--force', '--sign', '-', '--identifier',
                        'edgelessblade.opentypeless', str(app)], check=True, capture_output=True)
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
    except Exception:
        if staging.exists(): staging.unlink()
        shutil.copy2(backup / 'executable', executable)
        shutil.copy2(backup / 'Info.plist', info)
        subprocess.run(['codesign', '--force', '--sign', '-', '--identifier',
                        'edgelessblade.opentypeless', str(app)], capture_output=True)
        raise
    receipt = {
        'sourceRevision': revision,
        'sourceDirectory': str(source.resolve()),
        'appName': name,
        'binarySHA256': hashlib.sha256(executable.read_bytes()).hexdigest(),
        'privateDataCopied': False,
    }
    (target / 'LOCAL-BUILD.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('Updated local app code; private settings and credentials were not copied or changed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--name', default='Local Edgeless Type')
    args = parser.parse_args()
    source_binary = ROOT / 'edgelesstype.app/Contents/MacOS/edgelesstype'
    if not source_binary.is_file(): raise ValueError('Build the public-source app first')
    inputs = list((ROOT / 'Sources').rglob('*.swift')) + [ROOT / 'Package.swift']
    if any(p.stat().st_mtime > source_binary.stat().st_mtime for p in inputs):
        raise ValueError('Source changed since the build; rebuild first')
    subprocess.run(['python3', str(ROOT / 'Scripts/public-check.py'), '--app-only'], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(source_binary.parents[2])], check=True)
    running = subprocess.check_output(['ps', '-axo', 'comm='], text=True)
    target = args.target.resolve()
    if any(line.strip().startswith(str(target) + '/') and line.strip().endswith('/MacOS/edgelesstype')
           for line in running.splitlines()):
        raise ValueError('Quit the local app before updating')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()
    install(ROOT, target, args.name, revision + ('+local-changes' if dirty else ''))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError):
        raise SystemExit('Local update failed. Check paths, build, signature and whether the app is closed. No private files were synchronized.')
