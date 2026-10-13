#!/usr/bin/env python3
"""Select the user's existing Keychain signing identity without exporting private keys."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

LOCAL_ID = 'edgelessblade.opentypeless.local'
DEFAULT_NAME = 'Local Edgeless Type Signing'


def select_identity(output, name=None, fingerprint=None):
    identities = re.findall(r'^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+"([^"\n]+)"', output, re.MULTILINE)
    matches = [(sha.upper(), label) for sha, label in identities
               if (fingerprint and sha.upper() == fingerprint.upper()) or
                  (not fingerprint and label == name)]
    if len(matches) != 1:
        raise ValueError('A single valid matching code-signing identity is required; create it in Keychain Access or select an exact fingerprint')
    return matches[0][0]


def save_profile(target, fingerprint):
    if not target.is_dir() or not (target / 'Config/app.json').is_file():
        raise ValueError('Use an existing private runtime, not the public source checkout')
    source = Path(__file__).resolve().parent.parent
    if target.resolve() == source or source in target.resolve().parents:
        raise ValueError('Signing profile must stay outside the public checkout')
    path = target / 'LOCAL-SIGNING.json'
    profile = {'bundleIdentifier': LOCAL_ID, 'identitySHA1': fingerprint}
    if path.is_symlink(): raise ValueError('Refusing signing-profile symlink')
    if path.exists():
        if json.loads(path.read_text()) != profile:
            raise ValueError('An existing different signer must not be replaced automatically')
        print('Existing signing profile matches; no changes.')
        return
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as handle:
        handle.write(json.dumps(profile, indent=2) + '\n')
    print('Private signing profile created. No private key was read, copied or exported.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', type=Path, required=True)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--identity-name', default=DEFAULT_NAME)
    group.add_argument('--identity-sha1')
    args = parser.parse_args()
    if args.identity_sha1 and not re.fullmatch(r'[0-9A-Fa-f]{40}', args.identity_sha1):
        raise ValueError('Expected a certificate SHA-1 fingerprint')
    output = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'],
                            check=True, capture_output=True, text=True).stdout
    selected = select_identity(output, args.identity_name, args.identity_sha1)
    save_profile(args.target.resolve(), selected)


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if isinstance(error, ValueError): raise SystemExit(str(error))
        raise SystemExit('Could not inspect signing identity or write profile. No private key was exported.')
