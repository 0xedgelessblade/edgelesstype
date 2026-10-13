#!/usr/bin/env python3
"""Synthetic filesystem migration tests; no real keys, settings or network."""
from pathlib import Path
import importlib.util,json,tempfile
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('migration',Path(__file__).with_name('migrate-local-data.py'))
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def crypto(tool,operation,*paths):
    if operation=='convert':paths[-1].write_bytes(b'synthetic-v2-ciphertext')
    elif operation=='verify':assert paths[-1].read_bytes()==b'synthetic-v2-ciphertext'

def fixture(root,missing_asset=False):
    root=root.resolve()
    runtime=root/'runtime';keys=root/'keys'
    (runtime/'Config').mkdir(parents=True);(runtime/'private').mkdir();(runtime/'Models').mkdir();keys.mkdir()
    (runtime/'Models/model.bin').write_bytes(b'synthetic-model')
    old=root/'previous'
    config={'modelPath':str(old/'Models'/('missing.bin' if missing_asset else 'model.bin')),'terms':['synthetic-vocabulary'],'cloudChoice':'unchanged'}
    (runtime/'Config/app.json').write_text(json.dumps(config))
    (runtime/'Config/vocabulary.json').write_text('{"entries":["synthetic"]}')
    (runtime/m.OLD_STORE).write_bytes(b'synthetic-v1-ciphertext')
    (keys/m.OLD_KEY).write_bytes(b'synthetic-key-table')
    (keys/m.MARKERS[0][0]).write_bytes(b'synthetic-permission-marker')
    return runtime,keys,old

with tempfile.TemporaryDirectory() as directory:
    root=Path(directory);runtime,keys,old=fixture(root)
    dictionary=(runtime/'Config/vocabulary.json').read_bytes()
    with patch.object(m,'crypto',side_effect=crypto):
        backup=m.migrate(runtime,keys,Path('unused'),[str(old)])
        assert (keys/m.OLD_KEY).exists() and (runtime/m.OLD_STORE).exists()
        assert (runtime/m.NEW_STORE).stat().st_mode & 0o777 == 0o600
        assert (keys/m.NEW_KEY).stat().st_mode & 0o777 == 0o600
        assert not list((backup/'files').rglob('*keyring*'))
        assert (keys/'edgelesstype-backups'/backup.name/m.OLD_KEY).read_bytes()==b'synthetic-key-table'
        assert (runtime/'Config/vocabulary.json').read_bytes()==dictionary
        assert json.loads((runtime/'Config/app.json').read_text())['modelPath']==str(runtime/'Models/model.bin')
        assert m.migrate(runtime,keys,Path('unused'),[str(old)])==backup
        m.finalize(runtime,keys,backup,Path('unused'))
        assert not (keys/m.OLD_KEY).exists() and not (runtime/m.OLD_STORE).exists()
        assert (backup/'files'/m.OLD_STORE).read_bytes()==b'synthetic-v1-ciphertext'
        assert (runtime/'Models/model.bin').read_bytes()==b'synthetic-model'
print('PASS separated verified backups, unchanged dictionary/model, v2 preparation, path migration, idempotence and legacy retirement')
with tempfile.TemporaryDirectory() as directory:
    runtime,keys,old=fixture(Path(directory),missing_asset=True)
    original=(runtime/'Config/app.json').read_bytes()
    with patch.object(m,'crypto',side_effect=crypto):
        try:m.migrate(runtime,keys,Path('unused'),[str(old)])
        except ValueError:pass
        else:raise AssertionError('Missing asset accepted')
    assert (runtime/'Config/app.json').read_bytes()==original
    assert not (runtime/m.NEW_STORE).exists() and not (keys/m.NEW_KEY).exists()
    assert (runtime/m.OLD_STORE).exists() and (keys/m.OLD_KEY).exists()
print('PASS failure rolls back private files without plaintext output')
with tempfile.TemporaryDirectory() as directory:
    runtime,keys,old=fixture(Path(directory))
    (keys/m.NEW_KEY).write_bytes(b'unrelated existing destination')
    with patch.object(m,'crypto',side_effect=crypto):
        try:m.migrate(runtime,keys,Path('unused'),[str(old)])
        except ValueError:pass
        else:raise AssertionError('Conflicting destination overwritten')
    assert (keys/m.NEW_KEY).read_bytes()==b'unrelated existing destination'
print('PASS conflicting destinations are never overwritten')
