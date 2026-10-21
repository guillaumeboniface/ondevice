#!/usr/bin/env python3
"""Materialize official, checksum-verified binaries so Xcode builds need no network."""
import hashlib, json, pathlib, re, subprocess, zipfile, plistlib, shutil
root = pathlib.Path(__file__).resolve().parents[1]
cache = root / '.build/downloads'
cache.mkdir(parents=True, exist_ok=True)
entries = [
 ('moonshine', 'Moonshine', 'https://github.com/moonshine-ai/moonshine-swift/releases/download/v0.1.5/Moonshine.xcframework.zip',
  '6bc7fb4b6d3a470a2ae2d681299975f3ba9d710753786d1cd7e8beabaad066e8'),
 ('phonon', 'PhononCore', 'https://github.com/gradium-ai/xn-ptts/releases/download/v0.4.0/PhononCore.xcframework.zip',
  'a10382948448087bc9f63231de3c2970d606979fd69bef7acb95d2dfa3a41cef')
]
for package, name, url, digest in entries:
    archive = cache / (name + '.xcframework.zip')
    if not archive.exists():
        subprocess.run(['curl', '-fL', '--retry', '3', '--speed-time', '30', '--speed-limit', '1024',
                        '--silent', '--show-error', url, '-o', str(archive)], check=True)
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != digest:
            raise RuntimeError(f'Binary checksum mismatch: {name}')
    destination = root / 'vendor' / package
    if not (destination / (name + '.xcframework')).exists():
        subprocess.run(['ditto', '-xk', str(archive), str(destination)], check=True)
    manifest = destination / 'Package.swift'
    text = subprocess.check_output(['git', '-C', str(destination), 'show', 'HEAD:Package.swift'], text=True)
    text, count = re.subn(r'\.binaryTarget\([\s\S]*?\n        \)',
                         f'.binaryTarget(name: "{name}", path: "{name}.xcframework")', text, count=1)
    if count == 0 and f'path: "{name}.xcframework"' not in text:
        raise RuntimeError(f'Cannot patch binary target: {manifest}')
    manifest.write_text(text)
    print('Local binary ready:', name)

# Two static-library XCFrameworks otherwise both copy include/module.modulemap.
# Wrap Phonon's unchanged static archives in uniquely named static frameworks.
xcframework = root / 'vendor/phonon/PhononCore.xcframework'
info_path = xcframework / 'Info.plist'
info = plistlib.loads(info_path.read_bytes())
for library in info['AvailableLibraries']:
    if library['LibraryPath'].endswith('.framework'): continue
    platform = xcframework / library['LibraryIdentifier']
    framework = platform / 'PhononCore.framework'
    framework.mkdir(exist_ok=True)
    shutil.move(str(platform / library['LibraryPath']), str(framework / 'PhononCore'))
    shutil.move(str(platform / library['HeadersPath']), str(framework / 'Headers'))
    (framework / 'Headers/module.modulemap').unlink()
    (framework / 'Modules').mkdir(exist_ok=True)
    (framework / 'Modules/module.modulemap').write_text('framework module PhononCore {\n  umbrella header "ptts.h"\n  export *\n}\n')
    (framework / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleExecutable': 'PhononCore', 'CFBundleIdentifier': 'ai.gradium.PhononCore',
        'CFBundleName': 'PhononCore', 'CFBundlePackageType': 'FMWK',
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '0.4.0'
    }))
    library['LibraryPath'] = 'PhononCore.framework'
    library['BinaryPath'] = 'PhononCore.framework/PhononCore'
    del library['HeadersPath']
info_path.write_bytes(plistlib.dumps(info))
print('Phonon static framework wrapper ready (no runtime changes)')
