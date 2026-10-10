#!/usr/bin/env python3
"""Create a private, relocatable Apple-silicon transfer folder. No credentials.
Build release first; sign the resulting app after packaging, then archive the entire folder."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

def run(*args):
    return subprocess.check_output(args, text=True)

def dependencies(path):
    return [line.strip().split(' (')[0] for line in run('otool', '-L', str(path)).splitlines()[1:]]

def copy_recorder(source, engine, notices):
    source = Path(source).resolve()
    pending = [source]
    mapping = {}
    while pending:
        item = pending.pop()
        if item in mapping:
            continue
        dest = engine / ('ffmpeg' if item == source else 'lib/' + item.name)
        assert dest not in mapping.values(), 'Dependency filename collision'
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, dest)
        mapping[item] = dest
        for dep in dependencies(item):
            if dep.startswith('/System/') or dep.startswith('/usr/lib/'):
                continue
            assert dep.startswith('/'), f'Unresolved dependency: {dep}'
            actual = Path(dep).resolve()
            if actual != item:
                pending.append(actual)
    for source, dest in mapping.items():
        subprocess.run(['codesign', '--remove-signature', str(dest)], capture_output=True)
        changes = []
        for dep in dependencies(source):
            actual = Path(dep).resolve() if dep.startswith('/') else None
            if actual in mapping:
                relative = os.path.relpath(mapping[actual], dest.parent)
                changes.extend(['-change', dep, '@loader_path/' + relative])
        if dest.suffix == '.dylib':
            changes.extend(['-id', '@loader_path/' + dest.name])
        if changes:
            subprocess.run(['install_name_tool', *changes, str(dest)], check=True, capture_output=True)
        subprocess.run(['codesign', '--force', '--sign', '-', str(dest)], check=True, capture_output=True)
        assert all(x.startswith(('/System/', '/usr/lib/', '@loader_path/')) for x in dependencies(dest))
        # Include local formula notices without copying Homebrew receipts or user paths.
        parts = source.parts
        if 'Cellar' in parts:
            i = parts.index('Cellar')
            formula = Path(*parts[:i+3])
            notice_dir = notices / (parts[i+1] + '-' + parts[i+2])
            for notice in formula.iterdir():
                if notice.is_file() and notice.name.upper().startswith(('LICENSE', 'COPYING', 'COPYRIGHT')):
                    notice_dir.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(notice, notice_dir / notice.name)
    return len(mapping)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    root, dest = args.root.resolve(), args.destination.resolve()
    assert not dest.exists(), 'Destination must be new'
    dest.mkdir(parents=True)
    config = json.loads((root / 'Config/app.example.json').read_text())
    original = json.loads(json.dumps(config))
    local_config = json.loads((root / 'Config/app.json').read_text())
    original['ffmpegPath'] = local_config['ffmpegPath']
    for name in ['serverPath', 'turboModelPath', 'smallModelPath']:
        original['residentSpeech'][name] = str(root / original['residentSpeech'][name])
    app = dest / 'edgelesstype.app'
    source_app = root / 'edgelesstype.app'
    if not source_app.exists():
        source_app = root / 'OpenTypeless.app'
    shutil.copytree(source_app, app)
    old_executable = app / 'Contents/MacOS/OpenTypeless'
    if old_executable.exists():
        old_executable.unlink()
    shutil.copy2(root / '.build/release/edgelesstype', app / 'Contents/MacOS/edgelesstype')
    for folder in ['Config', 'Engine', 'Models', 'Licenses']:
        (dest / folder).mkdir()
    shutil.copy2(original['residentSpeech']['serverPath'], dest / 'Engine/whisper-server')
    shutil.copy2(original['residentSpeech']['turboModelPath'], dest / 'Models/ggml-large-v3-turbo.bin')
    shutil.copy2(original['residentSpeech']['smallModelPath'], dest / 'Models/ggml-small.bin')
    vad_name = 'ggml-silero-v5.1.2.bin'
    shutil.copy2(root / original['residentSpeech'].get('vadModelPath', 'Models/' + vad_name), dest / 'Models' / vad_name)
    config['residentSpeech']['vadModelPath'] = 'Models/' + vad_name
    count = copy_recorder(original['ffmpegPath'], dest / 'Engine', dest / 'Licenses')
    # The portable edition always uses the resident engine for both models.
    config['whisperCLI'] = ''
    config['modelPath'] = 'Models/ggml-small.bin'
    config['ffmpegPath'] = 'Engine/ffmpeg'
    config['residentSpeech'].update(serverPath='Engine/whisper-server',
        smallModelPath='Models/ggml-small.bin', turboModelPath='Models/ggml-large-v3-turbo.bin')
    serialized = json.dumps(config, ensure_ascii=False, indent=2) + '\n'
    (dest / 'Config/app.json').write_text(serialized)
    (app / 'Contents/Resources/app.json').write_text(serialized)
    import uuid
    words = json.loads((root / 'Config/dictionary-seed.json').read_text())
    vocabulary = {'version': 1, 'contextCorrectionEnabled': False,
                  'entries': [{'id': str(uuid.uuid4()).upper(), 'word': word, 'misheard': [], 'context': ''} for word in words]}
    (dest / 'Config/vocabulary.json').write_text(json.dumps(vocabulary, ensure_ascii=False, indent=2)+'\n')
    plist = app / 'Contents/Info.plist'
    info = plistlib.loads(plist.read_bytes())
    info['LSMinimumSystemVersion'] = '26.0'
    info.update(CFBundleExecutable='edgelesstype', CFBundleName='edgelesstype', CFBundleDisplayName='edgelesstype')
    plist.write_bytes(plistlib.dumps(info))
    for name in ['LICENSE', 'README.md']:
        source = root / 'ThirdParty/whisper-a91dd3be72f70dd1b3cb6e252f35fa17b93f596c' / name
        if source.exists():
            shutil.copy2(source, dest / 'Licenses' / ('whisper-' + name))
    (dest / 'Licenses/來源.txt').write_text('本移轉包供使用者在自己的 Mac 使用。\nwhisper.cpp v1.8.1: https://github.com/ggml-org/whisper.cpp/tree/v1.8.1\nWhisper models: https://huggingface.co/ggerganov/whisper.cpp\nFFmpeg: https://ffmpeg.org/ （包含 GPL 元件；授權文件見本資料夾）\n')
    for resource in (root / "Resources/Portable").iterdir():
        if resource.is_file():
            shutil.copy2(resource, dest / resource.name)
    print(f'portableFolderReady=true recorderBinaries={count}', flush=True)

if __name__ == '__main__':
    main()
