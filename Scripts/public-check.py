#!/usr/bin/env python3
"""Check exactly the public source allowlist; never print matching values."""
from pathlib import Path
import json
import re
import sys
import argparse
import subprocess
import zipfile

root = Path(__file__).resolve().parent.parent
TOP_FILES = ['Package.swift', '.gitignore', 'README.md', 'AGENTS.md', 'LICENSE', 'SECURITY.md', 'DEVELOPMENT.md', 'CONTRIBUTING.md', 'CITATION.cff', 'llms.txt', '打開 edgelesstype.command']
DIRECTORIES = ['Sources', 'Tests', 'Scripts', 'Resources', 'Patches', '.github', 'docs']
CONFIG = ['Config/app.example.json', 'Config/dictionary-seed.json']
def public_files():
    result = [root/p for p in TOP_FILES+CONFIG if (root/p).is_file()]
    for folder in DIRECTORIES:
        result += [p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name != '.DS_Store']
    return sorted(set(result))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?")
    parser.add_argument("--binaries", action="store_true")
    parser.add_argument("--app-only", action="store_true", help="Check the app binary without requiring the optional local engine build")
    args = parser.parse_args()
    patterns = {
        'absolute-user-home': re.compile(rb'/Users/[A-Za-z0-9_.-]+/'),
        'credential': re.compile(rb'(?:xai-|sk-(?:proj-|ant-)?|gh[pousr]_|github_pat_)[A-Za-z0-9_-]{24,}'),
        'private-key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
        'personal-email': re.compile(rb'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
    }
    errors = []
    files = public_files()
    for required in TOP_FILES+CONFIG:
        if not (root/required).is_file(): errors.append((required, 'missing'))
    for p in files:
        data=p.read_bytes()
        for label, pattern in patterns.items():
            if pattern.search(data): errors.append((str(p.relative_to(root)),label))
        if p.is_symlink(): errors.append((str(p.relative_to(root)),'symlink'))
    if (root/'.git').is_dir():
        tracked = subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
        allowed = {str(p.relative_to(root)) for p in files}
        for name in tracked:
            if name and name not in allowed: errors.append((name,'not-in-public-allowlist'))
    words=json.loads((root/'Config/dictionary-seed.json').read_text())
    if any(re.search(r'[\u3400-\u9fff]',word) for word in words): errors.append(('Config/dictionary-seed.json','Chinese-seed-entry'))
    if args.binaries or args.app_only:
        binaries = ['edgelesstype.app/Contents/MacOS/edgelesstype']
        if args.binaries: binaries.append('Engine/whisper-server')
        for name in binaries:
            p = root/name
            if not p.is_file(): errors.append((name,'missing-binary')); continue
            data = p.read_bytes()
            for label, pattern in patterns.items():
                if pattern.search(data): errors.append((name,label))
    if errors:
        for path, label in errors: print(f'FAIL {path}: {label}')
        return 1
    print(f'PASS public source: {len(files)} files, {len(words)} English seed words')
    if args.output:
        output=Path(args.output).resolve()
        output.parent.mkdir(parents=True,exist_ok=True)
        with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED) as archive:
            for p in files:
                info = zipfile.ZipInfo(str(Path('Github-EdgelessType')/p.relative_to(root)), date_time=(2026,1,1,0,0,0))
                info.create_system = 3
                info.external_attr = (p.stat().st_mode & 0xffff) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info,p.read_bytes())
        print('Public source ZIP created; runtime settings, keys, binaries, history and models excluded.')
    return 0

if __name__=='__main__': raise SystemExit(main())
