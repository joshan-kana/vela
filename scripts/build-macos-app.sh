#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-Debug}"

case "$configuration" in
  Release)
    profile="release"
    optimization=(-O)
    default_archs="arm64 x86_64"
    ;;
  *)
    profile="debug"
    optimization=(-Onone -g)
    default_archs="$(uname -m)"
    ;;
esac

requested_archs="${ARCHS:-$default_archs}"
app_dir="$repo_root/apps/macos/build/$configuration/Vela.app"
contents="$app_dir/Contents"
binary_dir="$contents/MacOS"
temp_dir="$repo_root/apps/macos/build/.swift-$configuration"

rm -rf "$app_dir" "$temp_dir"
mkdir -p "$binary_dir" "$contents/Resources" "$temp_dir"

ARCHS="$requested_archs" "$repo_root/scripts/build-rust-macos.sh" "$configuration"

sdk="$(xcrun --sdk macosx --show-sdk-path)"
rust_archive="$repo_root/target/vela-macos/$profile/libvela_ffi.a"
ffi_header="$repo_root/crates/vela-ffi/include/vela_ffi.h"
sources=("$repo_root"/apps/macos/Sources/VelaMacOS/*.swift)
binaries=()

for arch in $requested_archs; do
  case "$arch" in
    arm64)
      swift_target="arm64-apple-macos14.0"
      ;;
    x86_64)
      swift_target="x86_64-apple-macos14.0"
      ;;
    *)
      echo "error: unsupported macOS architecture: $arch" >&2
      exit 1
      ;;
  esac

  output="$temp_dir/Vela-$arch"

  swift_args=(
    "${optimization[@]}"
    -target "$swift_target"
    -sdk "$sdk"
    -import-objc-header "$ffi_header"
    -framework AppKit
    -framework CoreFoundation
    -framework Security
    -framework SystemConfiguration
    -Xlinker -liconv
    "${sources[@]}"
    "$rust_archive"
    -o "$output"
  )

  xcrun swiftc "${swift_args[@]}"
  binaries+=("$output")
done

if [[ ${#binaries[@]} -eq 1 ]]; then
  cp "${binaries[0]}" "$binary_dir/Vela"
else
  xcrun lipo -create "${binaries[@]}" -output "$binary_dir/Vela"
fi

cp "$repo_root/apps/macos/Info.plist" "$contents/Info.plist"
codesign --force --sign - "$app_dir" >/dev/null

echo "$app_dir"
