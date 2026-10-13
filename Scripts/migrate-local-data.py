#!/usr/bin/env python3
"""Explicit offline v2 migration with separate key backups; never prints private contents."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parent.parent
OLD_KEY = 'open-typeless-keyring.json'
NEW_KEY = 'edgelesstype-keyring.json'
OLD_STORE = 'private/store.encrypted.json'
NEW_STORE = 'private/credentials.encrypted.json'
MARKERS = [('open-typeless-explained', 'edgelesstype-explained'), ('open-typeless-status.txt', 'edgelesstype-status.txt')]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    temporary = path.with_name(path.name + '.migration-tmp')
    with temporary.open('x') as handle:
        os.chmod(temporary, 0o600)
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')
        handle.flush(); os.fsync(handle.fileno())
    os.replace(temporary, path)


def safe_file(path):
    if path.is_symlink() or any(p.is_symlink() for p in path.parents):
        raise ValueError('Symlink paths are not supported for migration')


def crypto(tool, operation, *paths):
    subprocess.run([str(tool), operation, *map(str, paths)], check=True, capture_output=True)


def migrate(runtime, secrets, tool, previous_roots):
    os.umask(0o077)
    runtime = runtime.absolute(); secrets = secrets.absolute()
    for p in [runtime, secrets, runtime / OLD_STORE, runtime / NEW_STORE, secrets / OLD_KEY, secrets / NEW_KEY]: safe_file(p)
    if runtime.resolve() == ROOT or ROOT in runtime.resolve().parents:
        raise ValueError('Private runtime must be separate from source checkout')
    if any(x in str(secrets) for x in ['CloudStorage', 'GoogleDrive', '其他電腦']):
        raise ValueError('Key table must stay in a local unsynced directory')
    if not (runtime / 'Config/app.json').is_file(): raise ValueError('Missing runtime config')
    marker = runtime / 'LOCAL-DATA.json'
    if marker.exists():
        state = json.loads(marker.read_text())
        if state.get('version') != 2: raise ValueError('Unexpected migration state')
        if (runtime / NEW_STORE).exists(): crypto(tool, 'verify', secrets / NEW_KEY, runtime / NEW_STORE)
        print('Already migrated; existing v2 data verified.')
        return runtime / '.private-backups' / state['migration']
    if (runtime / NEW_STORE).exists() or (secrets / NEW_KEY).exists():
        raise ValueError('Destination exists without a completed migration marker; inspect before retrying')
    migration = 'migration-' + uuid.uuid4().hex
    backup = runtime / '.private-backups' / migration
    key_backup = secrets / 'edgelesstype-backups' / migration
    backup.mkdir(parents=True, mode=0o700); key_backup.mkdir(parents=True, mode=0o700)
    os.chmod(backup.parent,0o700); os.chmod(key_backup.parent,0o700)
    journal = {'version': 2, 'phase': 'backed_up', 'snapshots': [], 'created': [], 'changed': []}
    def snapshot(area, relative):
        base = runtime if area == 'runtime' else secrets
        destination = backup / 'files' if area == 'runtime' else key_backup
        src = base / relative
        safe_file(src)
        if not src.is_file(): return
        dst = destination / relative; dst.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copyfile(src, dst); os.chmod(dst,0o600)
        if digest(src) != digest(dst): raise ValueError('Backup verification failed')
        journal['snapshots'].append({'area':area,'path':relative,'sha256':digest(dst)})
    for p in sorted((runtime / 'Config').rglob('*')):
        if p.is_file() or p.is_symlink(): snapshot('runtime',str(p.relative_to(runtime)))
    for relative in [OLD_STORE,'LOCAL-BUILD.json','LOCAL-SIGNING.json']:
        snapshot('runtime',relative)
    for relative in [OLD_KEY] + [a for a,b in MARKERS]: snapshot('keys',relative)
    write_json(backup/'manifest.json',journal)
    stage = runtime / 'private/.credentials-migration-stage'
    try:
        if (runtime / OLD_STORE).exists():
            if not (secrets / OLD_KEY).is_file(): raise ValueError('Missing matching key table')
            crypto(tool,'convert',secrets/OLD_KEY,runtime/OLD_STORE,stage)
            crypto(tool,'verify',secrets/OLD_KEY,stage)
        if (secrets / OLD_KEY).exists():
            shutil.copyfile(secrets/OLD_KEY,secrets/NEW_KEY);os.chmod(secrets/NEW_KEY,0o600)
            journal['created'].append({'area':'keys','path':NEW_KEY,'sha256':digest(secrets/NEW_KEY)})
        if stage.exists():
            stage.rename(runtime/NEW_STORE)
            journal['created'].append({'area':'runtime','path':NEW_STORE,'sha256':digest(runtime/NEW_STORE)})
        for old,new in MARKERS:
            if (secrets/old).exists():
                if (secrets/new).exists(): raise ValueError('Marker destination already exists')
                shutil.copyfile(secrets/old,secrets/new);os.chmod(secrets/new,0o600)
                journal['created'].append({'area':'keys','path':new,'sha256':digest(secrets/new)})
        config = runtime / 'Config/app.json'
        value=json.loads(config.read_text())
        def rewrite(x):
            if isinstance(x,str):
                for old in previous_roots:
                    old=old.rstrip('/')
                    if x==old or x.startswith(old+'/'):return str(runtime)+x[len(old):]
                return x
            if isinstance(x,list):return [rewrite(y) for y in x]
            if isinstance(x,dict):return {k:rewrite(v) for k,v in x.items()}
            return x
        migrated=rewrite(value)
        if migrated!=value:
            write_json(config,migrated)
            journal['changed'].append({'area':'runtime','path':'Config/app.json','sha256':digest(config)})
        # Check only known executable/model paths; never print settings values.
        for value in [migrated.get('ffmpegPath'),migrated.get('whisperCLI'),migrated.get('modelPath')] + [(migrated.get('residentSpeech') or {}).get(k) for k in ['serverPath','smallModelPath','turboModelPath','vadModelPath']]:
            if isinstance(value,str) and value:
                asset=Path(value) if value.startswith('/') else runtime/value
                if not asset.exists():raise ValueError('Configured runtime asset is missing')
        if (runtime/NEW_STORE).exists():crypto(tool,'verify',secrets/NEW_KEY,runtime/NEW_STORE)
        write_json(marker,{'version':2,'migration':migration})
        journal['created'].append({'area':'runtime','path':'LOCAL-DATA.json','sha256':digest(marker)})
        journal['phase']='prepared';write_json(backup/'manifest.json',journal)
    except Exception:
        if stage.exists():stage.unlink()
        write_json(backup/'manifest.json',journal)
        rollback(runtime,secrets,backup)
        raise
    print('Migration prepared: verified local backups, ciphertext and runtime paths. Legacy files retained until finalization.')
    return backup


def rollback(runtime,secrets,backup):
    journal=json.loads((backup/'manifest.json').read_text())
    if journal['phase']=='finalized':raise ValueError('Finalized migration requires an explicit offline recovery plan')
    for entry in journal['created']+journal['changed']:
        p=(runtime if entry['area']=='runtime' else secrets)/entry['path']
        if p.exists() and digest(p)!=entry['sha256']:raise ValueError('Data changed after migration; refusing destructive rollback')
    for entry in journal['snapshots']:
        if not any(x['area']==entry['area'] and x['path']==entry['path'] for x in journal['changed']):continue
        source=(backup/'files' if entry['area']=='runtime' else secrets/'edgelesstype-backups'/backup.name)/entry['path']
        if digest(source)!=entry['sha256']:raise ValueError('Backup integrity check failed')
        target=(runtime if entry['area']=='runtime' else secrets)/entry['path']
        shutil.copyfile(source,target);os.chmod(target,0o600)
    for entry in journal['created']:
        p=(runtime if entry['area']=='runtime' else secrets)/entry['path']
        if p.exists():p.unlink()
    journal['phase']='rolled_back';write_json(backup/'manifest.json',journal)
    print('Migration rolled back; original data restored.')


def finalize(runtime,secrets,backup,tool):
    journal=json.loads((backup/'manifest.json').read_text())
    if journal['phase']=='finalized':print('Already finalized.');return
    if journal['phase']!='prepared':raise ValueError('Migration is not ready to finalize')
    if (runtime/NEW_STORE).exists():crypto(tool,'verify',secrets/NEW_KEY,runtime/NEW_STORE)
    legacy=[x for x in journal['snapshots'] if x['path']==OLD_STORE or x['area']=='keys']
    for entry in legacy:
        p=(runtime if entry['area']=='runtime' else secrets)/entry['path']
        if p.exists() and digest(p)!=entry['sha256']:raise ValueError('Legacy data changed; refusing retirement')
    for entry in legacy:
        p=(runtime if entry['area']=='runtime' else secrets)/entry['path']
        if p.exists():p.unlink()
    journal['phase']='finalized';write_json(backup/'manifest.json',journal)
    print('Migration finalized: only new-format active files remain; verified local backups retained separately.')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['prepare','finalize','rollback'])
    p.add_argument('--runtime',type=Path,required=True)
    p.add_argument('--key-directory',type=Path,default=Path.home()/'.config/codex-secrets')
    p.add_argument('--previous-root',action='append',default=[])
    p.add_argument('--backup',type=Path)
    p.add_argument('--crypto-tool',type=Path,default=ROOT/'.build/release/edgelesstype-data-migrate')
    args=p.parse_args();os.umask(0o077)
    running=subprocess.check_output(['ps','-axo','comm='],text=True)
    if any(x.strip().endswith('/Contents/MacOS/edgelesstype') for x in running.splitlines()):raise ValueError('Quit all running app copies before migration')
    if args.action=='prepare':migrate(args.runtime,args.key_directory,args.crypto_tool,args.previous_root)
    else:
        if not args.backup or args.backup.parent!=args.runtime/'.private-backups':raise ValueError('Use the matching runtime backup')
        if args.action=='finalize':finalize(args.runtime,args.key_directory,args.backup,args.crypto_tool)
        else:rollback(args.runtime,args.key_directory,args.backup)


if __name__=='__main__':
    try:main()
    except Exception:
        raise SystemExit('Local migration did not complete. Private contents were not printed. Inspect the private backup state before retrying.')
