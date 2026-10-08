#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-Debug}"
output_dir="${2:-$repo_root/apps/native/android/app/build/generated/vela-rust/${configuration,,}/jniLibs}"
platform="${ANDROID_PLATFORM:-24}"
requested_abis="${VELA_ANDROID_ABIS:-armeabi-v7a arm64-v8a x86 x86_64}"

cargo_args=(rustc --crate-type cdylib -p vela-ffi)
if [[ "$configuration" == "Release" ]]; then
  cargo_args+=(--release)
fi

ndk_version="$(
  sed -n 's/^[[:space:]]*ndkVersion = "\([^"]*\)".*/\1/p' "$repo_root/apps/native/android/build.gradle" |
    head -1
)"

if [[ -z "$ndk_version" ]]; then
  echo "error: could not determine Android NDK version" >&2
  exit 1
fi

ndk_dir="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

if [[ -z "$ndk_dir" ]]; then
  sdk_dirs=(
    "${ANDROID_HOME:-}"
    "${ANDROID_SDK_ROOT:-}"
    "$HOME/Library/Android/sdk"
    "$HOME/Android/Sdk"
  )

  for sdk_dir in "${sdk_dirs[@]}"; do
    [[ -n "$sdk_dir" ]] || continue

    candidate="$sdk_dir/ndk/$ndk_version"
    if [[ -d "$candidate" ]]; then
      ndk_dir="$candidate"
      break
    fi
  done
fi

if [[ ! -d "$ndk_dir" ]]; then
  echo "error: Android NDK $ndk_version was not found" >&2
  echo "Set ANDROID_NDK_HOME or install that NDK in your Android SDK." >&2
  exit 1
fi

cargo_ndk=(cargo ndk)
if ! command -v cargo-ndk >/dev/null 2>&1; then
  if command -v nix >/dev/null 2>&1; then
    cargo_ndk=(nix develop -c cargo ndk)
  elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
    cargo_ndk=(/nix/var/nix/profiles/default/bin/nix develop -c cargo ndk)
  else
    echo "error: cargo-ndk or nix is required to build the Android Rust library" >&2
    exit 1
  fi
fi

targets=()
for abi in $requested_abis; do
  case "$abi" in
    armeabi-v7a | arm64-v8a | x86 | x86_64)
      targets+=(--target "$abi")
      ;;
    *)
      echo "error: unsupported Android ABI: $abi" >&2
      exit 1
      ;;
  esac
done

rm -rf "$output_dir"
mkdir -p "$output_dir"

cd "$repo_root"

ANDROID_NDK_HOME="$ndk_dir" "${cargo_ndk[@]}" "${targets[@]}" --platform "$platform" --output-dir "$output_dir" "${cargo_args[@]}"
