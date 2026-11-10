#!/bin/sh
set -eu
cd "$SRCROOT/../.."
case "$PLATFORM_NAME" in
  macosx) VOW_TARGET=aarch64-apple-darwin ;;
  iphonesimulator) VOW_TARGET=aarch64-apple-ios-sim ;;
  iphoneos) VOW_TARGET=aarch64-apple-ios ;;
  *) echo "Unsupported platform: $PLATFORM_NAME" >&2; exit 1 ;;
esac
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
export VOW_WEBAUTHN_RP_ID="${VOW_WEBAUTHN_RP_ID:-}"
cargo +stable build --locked -p vow-ffi --target "$VOW_TARGET"
