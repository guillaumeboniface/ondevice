#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p vendor Frameworks
clone_pin() {
    local repository="$1" destination="$2" revision="$3"
    if [ ! -d "$destination/.git" ]; then
        git clone "$repository" "$destination"
    fi
    if [ "$(git -C "$destination" rev-parse HEAD)" != "$revision" ]; then
        git -C "$destination" fetch origin "$revision" --depth 1
        git -C "$destination" checkout --detach "$revision"
    fi
}
clone_pin https://github.com/moonshine-ai/moonshine-swift.git vendor/moonshine 45a14f9edf1f2a6913d3aff38c1fd4e72d5b7daa
clone_pin https://github.com/gradium-ai/xn-ptts.git vendor/phonon f07d7952db0c6127d5e4bc3f41c82b3304b6b5aa
python3 scripts/fetch_assets.py
python3 scripts/local_runtimes.py
python3 scripts/verify_assets.py --hash
xcodegen generate
