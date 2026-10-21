#!/usr/bin/env python3
"""Verify the produced app actually contains the provisioned models and dynamic runtime."""
import json, pathlib, sys
if len(sys.argv) != 2: sys.exit('Usage: verify_app_bundle.py path/to/OnDevice.app')
app = pathlib.Path(sys.argv[1])
root = pathlib.Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'bundled-models.lock.json').read_text())
for item in manifest['files']:
    bundled = app / 'Models' / item['path']
    if not bundled.is_file() or bundled.stat().st_size != item['bytes']:
        sys.exit(f'Incomplete app bundle: {bundled}')
if not (app / 'Models/assets.json').is_file(): sys.exit('Missing bundled asset manifest')
if not (app / 'Frameworks/llama.framework/llama').is_file(): sys.exit('Missing embedded dynamic llama framework')
if not (app / 'Licenses/NOTICE.txt').is_file(): sys.exit('Missing bundled notices')
print(f"App bundle verified: {len(manifest['files'])} model files, runtime and notices included")
