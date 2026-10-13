#!/usr/bin/env python3
"""Install reviewed code with a stable local signer; never sync private data back."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
LOCAL_ID = 'edgelessblade.opentypeless.local'
ASSETS = ('AppIcon.icns', 'start.wav', 'stop.wav', 'soft-start.wav',
          'soft-stop.wav', 'low-start.wav', 'low-stop.wav')


def load_signer(target):
    path = target / 'LOCAL-SIGNING.json'
    if path.is_symlink(): raise ValueError('Signing profile must not be a symlink')
    profile = json.loads(path.read_text())
    if (profile.get('bundleIdentifier') != LOCAL_ID or
            not re.fullmatch(r'[0-9A-Fa-f]{40}', profile.get('identitySHA1', ''))):
        raise ValueError('Stable local signing identity required; ad-hoc fallback is forbidden')
    return profile


def requirement(app):
    result = subprocess.run(['codesign', '-d', '-r-', str(app)],
                            check=True, capture_output=True, text=True)
    match = re.search(r'^designated => (.+)$', result.stdout + "\n" + result.stderr, re.MULTILINE)
    if not match or 'cdhash' in match[1] or not ('anchor' in match[1] or 'certificate' in match[1]):
        raise ValueError('Certificate-backed designated requirement required')
    return match[1]


def install(source, target, name, revision):
    if not name or name in ('.', '..') or '/' in name or '\\' in name:
        raise ValueError('Invalid local app name')
    if source.resolve() == target.resolve() or source.resolve() in target.resolve().parents:
        raise ValueError('Choose a separate private runtime directory')
    signer = load_signer(target)  # Fail before changing any app files.
    if not (target / 'Config/app.json').is_file():
        raise ValueError('Target must be an existing configured local installation')
    app = target / (name + '.app')
    contents = app / 'Contents'
    executable = contents / 'MacOS/edgelesstype'
    info = contents / 'Info.plist'
    if not executable.is_file() or not info.is_file():
        raise ValueError('Existing local app not found')
    metadata = plistlib.loads(info.read_bytes())
    previous_requirement = None
    if metadata.get('CFBundleIdentifier') == LOCAL_ID:
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
        previous_requirement = requirement(app)
    paths = ['MacOS/edgelesstype', 'Info.plist', '_CodeSignature/CodeResources']
    paths += ['Resources/' + asset for asset in ASSETS]
    for entry in [app, contents, contents / 'MacOS', contents / 'Resources', contents / '_CodeSignature'] + [contents / p for p in paths]:
        if entry.is_symlink(): raise ValueError('Local app paths must not be symlinks')
    backup_parent = target / '.build/local-update-backups'
    backup_parent.mkdir(parents=True, exist_ok=True)
    backup = Path(tempfile.mkdtemp(prefix='code-', dir=backup_parent))
    existing = set()
    for rel in paths:
        original = contents / rel
        if original.exists():
            existing.add(rel)
            dest = backup / rel; dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(original, dest)
    payload = source / 'edgelesstype.app/Contents'
    staging = executable.with_name('.edgelesstype-update')
    if staging.exists() or staging.is_symlink(): raise ValueError('Staging executable already exists')
    try:
        shutil.copy2(payload / 'MacOS/edgelesstype', staging)
        os.replace(staging, executable)
        metadata = plistlib.loads((payload / 'Info.plist').read_bytes())
        metadata.update(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=LOCAL_ID)
        info.write_bytes(plistlib.dumps(metadata))
        # No private settings or Resources/app.json are copied.
        for asset in ASSETS:
            item = payload / 'Resources' / asset
            if item.is_symlink(): raise ValueError('Source asset must not be a symlink')
            shutil.copy2(item, contents / 'Resources' / asset)
        subprocess.run(['codesign', '--force', '--sign', signer['identitySHA1'],
                        '--timestamp=none', '--identifier', LOCAL_ID, str(app)],
                       check=True, capture_output=True)
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
        new_requirement = requirement(app)
        if previous_requirement:
            subprocess.run(['codesign', '--verify', '--strict', '-R=' + previous_requirement, str(app)],
                           check=True, capture_output=True)
            if new_requirement != previous_requirement:
                raise ValueError('Signing identity changed; refusing a permission-breaking update')
    except Exception:
        if staging.exists(): staging.unlink()
        for rel in paths:
            dest = contents / rel
            if rel in existing:
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(backup / rel, dest)
            elif dest.exists(): dest.unlink()
        # Restore original signed bytes. Never re-sign a failed rollback ad hoc.
        raise
    receipt = {'sourceRevision': revision, 'sourceDirectory': str(source.resolve()),
               'appName': name, 'bundleIdentifier': LOCAL_ID,
               'designatedRequirement': new_requirement,
               'binarySHA256': hashlib.sha256(executable.read_bytes()).hexdigest(),
               'privateDataCopied': False}
    (target / 'LOCAL-BUILD.json').write_text(json.dumps(receipt, indent=2) + '\n')
    # Bundle-level mtime drives Finder/Spotlight identity caching. Updating only
    # the inner executable/plist can leave permission pickers using the old ID.
    os.utime(contents, None)
    os.utime(app, None)
    subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                    '-f', str(app)], check=True, capture_output=True)
    subprocess.run(['/usr/bin/mdimport', '-i', str(app)], check=True, capture_output=True)
    print('Updated local code with a stable signer; private data preserved.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', type=Path, required=True)
    parser.add_argument('--name', default='Local Edgeless Type')
    args = parser.parse_args()
    target = args.target.resolve()
    load_signer(target)
    source_binary = ROOT / 'edgelesstype.app/Contents/MacOS/edgelesstype'
    if not source_binary.is_file(): raise ValueError('Build the public-source app first')
    inputs = list((ROOT / 'Sources').rglob('*.swift')) + [ROOT / 'Package.swift']
    if any(p.stat().st_mtime > source_binary.stat().st_mtime for p in inputs):
        raise ValueError('Source changed since build; rebuild first')
    subprocess.run(['python3', str(ROOT / 'Scripts/public-check.py'), '--app-only'], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(source_binary.parents[2])], check=True)
    running = subprocess.check_output(['ps', '-axo', 'comm='], text=True)
    if any(line.strip().startswith(str(target) + '/') and line.strip().endswith('/MacOS/edgelesstype')
           for line in running.splitlines()): raise ValueError('Quit local app before updating')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()
    install(ROOT, target, args.name, revision + ('+local-changes' if dirty else ''))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError):
        raise SystemExit('Local update failed. Check signing profile, app state, build and paths. Ad-hoc fallback is not allowed; no private data was synchronized.')
