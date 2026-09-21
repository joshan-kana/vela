#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-Debug}"
platform_name="${PLATFORM_NAME:-iphonesimulator}"
requested_archs="${ARCHS:-arm64}"
deployment_target="${IPHONEOS_DEPLOYMENT_TARGET:-15.1}"

case "$configuration" in
  Release)
    cargo_profile="release"
    ;;
  *)
    cargo_profile="debug"
    ;;
esac

cd "$repo_root"

export IPHONEOS_DEPLOYMENT_TARGET="$deployment_target"

cargo_cmd=(cargo)
if ! command -v cargo >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1; then
    cargo_cmd=(nix develop -c cargo)
  elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
    cargo_cmd=(/nix/var/nix/profiles/default/bin/nix develop -c cargo)
  else
    echo "error: cargo or nix is required to build the Vela Rust core" >&2
    exit 1
  fi
fi

archives=()

for arch in $requested_archs; do
  case "$platform_name:$arch" in
    iphoneos:arm64)
      rust_target="aarch64-apple-ios"
      ;;
    iphonesimulator:arm64)
      rust_target="aarch64-apple-ios-sim"
      ;;
    iphonesimulator:x86_64)
      rust_target="x86_64-apple-ios"
      ;;
    *)
      echo "error: unsupported iOS platform/architecture: $platform_name/$arch" >&2
      exit 1
      ;;
  esac

  case "$platform_name" in
    iphoneos)
      sdk_name="iphoneos"
      ;;
    iphonesimulator)
      sdk_name="iphonesimulator"
      ;;
  esac

  target_env="${rust_target//-/_}"
  export "CC_${target_env}=$(xcrun --sdk "$sdk_name" -f clang)"
  export "CXX_${target_env}=$(xcrun --sdk "$sdk_name" -f clang++)"
  export "AR_${target_env}=$(xcrun --sdk "$sdk_name" -f ar)"
  export "RANLIB_${target_env}=$(xcrun --sdk "$sdk_name" -f ranlib)"

  if [[ "$cargo_profile" == "release" ]]; then
    "${cargo_cmd[@]}" build -p vela-ffi --target "$rust_target" --release
  else
    "${cargo_cmd[@]}" build -p vela-ffi --target "$rust_target"
  fi

  archives+=("$repo_root/target/$rust_target/$cargo_profile/libvela_ffi.a")
done

output_dir="$repo_root/target/vela-ios/$platform_name/$cargo_profile"
mkdir -p "$output_dir"
output="$output_dir/libvela_ffi.a"

if [[ ${#archives[@]} -eq 1 ]]; then
  cp "${archives[0]}" "$output"
else
  xcrun lipo -create "${archives[@]}" -output "$output"
fi
