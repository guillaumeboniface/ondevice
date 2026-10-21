#!/usr/bin/env python3
"""Developer-only asset provisioning. Never called by the iOS app or an Xcode build."""
import hashlib, json, pathlib, shutil, subprocess, urllib.request, zipfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
MODELS = ROOT / 'App/Resources/Models'
CACHE = ROOT / '.build/downloads'
CACHE.mkdir(parents=True, exist_ok=True)
MODELS.mkdir(parents=True, exist_ok=True)

def fetch(url, dest, sha=None):
    lock = ROOT / 'bundled-models.lock.json'
    if lock.exists() and dest.is_relative_to(MODELS):
        entries = json.loads(lock.read_text())['files']
        expected = next((f for f in entries if f['path'] == str(dest.relative_to(MODELS))), None)
        if expected: sha = expected['sha256']
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        print('Fetching', dest.name, flush=True)
        part = dest.with_suffix(dest.suffix + '.part')
        subprocess.run(['curl', '-fL', '--retry', '3', '--speed-time', '30', '--speed-limit', '1024', '--silent', '--show-error', url, '-o', str(part)], check=True)
        part.rename(dest)
    digest = hashlib.file_digest(dest.open('rb'), 'sha256').hexdigest()
    if sha and digest != sha:
        raise RuntimeError(f'Checksum mismatch: {dest}')
    return digest

# Published Phonon 0.4.0 Core ML release, including the English voice catalog.
phonon = CACHE / 'phonon-31m-en-coreml.zip'
fetch('https://github.com/gradium-ai/xn-ptts/releases/download/v0.4.0/phonon-31m-en-coreml.zip', phonon,
      '10f3a99fd39256db44f826267ef21d78cca959b16c0554926344c09fde27b436')
if not (MODELS / 'phonon/bundle.json').exists():
    unpack = CACHE / 'phonon-unpacked'
    with zipfile.ZipFile(phonon) as z: z.extractall(unpack)
    bundles = list(unpack.rglob('bundle.json'))
    if len(bundles) != 1: raise RuntimeError('Unexpected Phonon archive layout')
    shutil.copytree(bundles[0].parent, MODELS / 'phonon', dirs_exist_ok=True)

base = 'https://download.moonshine.ai/model/small-streaming-en/quantized_26_08_21'
for name in ['adapter.ort', 'cross_kv.ort', 'decoder_kv.ort', 'encoder.ort',
             'frontend.model.ort', 'frontend.weights.ort', 'streaming_config.json', 'tokenizer.bin']:
    fetch(f'{base}/{name}', MODELS / 'moonshine' / name)

revision = '7d26695454df6de5fbcce2e58681e62dae06ce43'
repo = 'bartowski/Qwen_Qwen3.5-2B-GGUF'
filename = 'Qwen_Qwen3.5-2B-Q4_K_M.gguf'
# Resolve LFS content hash from the pinned revision rather than trusting a filename.
metadata = json.loads(subprocess.check_output(['curl', '-fsSL', f'https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true']))
entry = next(f for f in metadata['siblings'] if f['rfilename'] == filename)
fetch(f'https://huggingface.co/{repo}/resolve/{revision}/{filename}', MODELS / 'llm/model.gguf', entry['lfs']['sha256'])

# iOS + simulator + macOS binary from the same llama.cpp revision used for API verification.
llama = CACHE / 'llama-b11786-xcframework.zip'
fetch('https://github.com/ggml-org/llama.cpp/releases/download/b11786/llama-b11786-xcframework.zip', llama,
      'c09d6f23b9b2520635693caa99c66084500b63c7004cff9b2a34d3f7b97af6b0')
if not (ROOT / 'Frameworks/llama.xcframework').exists():
    subprocess.run(['ditto', '-xk', str(llama), str(ROOT / 'Frameworks')], check=True)
    nested = ROOT / 'Frameworks/build-apple/llama.xcframework'
    if nested.exists(): shutil.move(str(nested), str(ROOT / 'Frameworks/llama.xcframework'))

manifest = {'schema': 1, 'stack': 'Moonshine Small Streaming / Qwen3.5-2B Q4_K_M / Phonon 31M Core ML',
            'qwenRevision': revision, 'files': []}
for p in sorted(MODELS.rglob('*')):
    if p.is_file() and p.name not in ('assets.json', '.gitkeep'):
        manifest['files'].append({'path': str(p.relative_to(MODELS)), 'bytes': p.stat().st_size,
                                  'sha256': hashlib.file_digest(p.open('rb'), 'sha256').hexdigest()})
(MODELS / 'assets.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f"Assets ready: {sum(x['bytes'] for x in manifest['files']) / 1e9:.2f} GB", flush=True)
