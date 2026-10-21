#!/usr/bin/env python3
import json, pathlib, sys, hashlib
root = pathlib.Path(__file__).resolve().parents[1] / 'App/Resources/Models'
manifest = root / 'assets.json'
if not manifest.exists():
    sys.exit('Bundled models are missing. Run python3 scripts/fetch_assets.py on the development Mac first.')
for f in json.loads(manifest.read_text())['files']:
    path = root / f['path']
    if not path.is_file() or path.stat().st_size != f['bytes']:
        sys.exit(f'Missing or incomplete bundled model: {path}')
    if '--hash' in sys.argv and hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != f['sha256']:
        sys.exit(f'Checksum mismatch: {path}')
print('Bundled model verification passed' + (' (SHA-256)' if '--hash' in sys.argv else ' (sizes)'))
