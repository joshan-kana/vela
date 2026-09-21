#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Skipping native macOS checks outside Darwin."
  exit 0
fi

cd "$repo_root"

bash -n   scripts/build-rust-macos.sh   scripts/build-macos-app.sh   scripts/check-macos-app.sh

swift-format lint --strict --recursive apps/macos/Sources/VelaMacOS
plutil -lint apps/macos/Info.plist >/dev/null

app_path="$(./scripts/build-macos-app.sh Debug)"
codesign --verify --deep --strict "$app_path"
