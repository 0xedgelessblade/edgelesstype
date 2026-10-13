#!/usr/bin/env python3
"""Synthetic metadata tests: no Keychain access and no real signing identity."""
from pathlib import Path
import importlib.util
import tempfile
import json

spec=importlib.util.spec_from_file_location('signing_config',Path(__file__).with_name('configure-local-signing.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
a='A'*40;b='B'*40
listing=f'  1) {a} "Local Edgeless Type Signing"\n  2) {b} "Other Signing Identity"\n  2 valid identities found\n'
assert m.select_identity(listing,name=m.DEFAULT_NAME)==a
assert m.select_identity(listing,fingerprint=b.lower())==b
for bad in ['', listing+f'  3) {b} "Local Edgeless Type Signing"\n']:
    try:m.select_identity(bad,name=m.DEFAULT_NAME)
    except ValueError:pass
    else:raise AssertionError('Missing or ambiguous signer was accepted')
print('PASS exact selection, missing identity and ambiguous identity')
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);(root/'Config').mkdir();(root/'Config/app.json').write_text('synthetic private settings')
    m.save_profile(root,a);p=root/'LOCAL-SIGNING.json';data=p.read_bytes()
    assert p.stat().st_mode & 0o777 == 0o600
    assert json.loads(data)=={'bundleIdentifier':m.LOCAL_ID,'identitySHA1':a}
    m.save_profile(root,a);assert p.read_bytes()==data
    try:m.save_profile(root,b)
    except ValueError:pass
    else:raise AssertionError('Existing signer changed')
    assert p.read_bytes()==data and (root/'Config/app.json').read_text()=='synthetic private settings'
    p.unlink();p.symlink_to(root/'Config/app.json')
    try:m.save_profile(root,a)
    except ValueError:pass
    else:raise AssertionError('Symlink accepted')
print('PASS mode 0600, idempotence, rotation rejection, private settings preservation and symlink rejection')
