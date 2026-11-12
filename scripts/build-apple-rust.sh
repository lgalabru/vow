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

# The Mac app carries the `vow` command line. It sits in Helpers because the
# app's own executable is `Vow` and the default volume ignores case.
if [ "$PLATFORM_NAME" = macosx ]; then
  cargo +stable build --locked -p vow-cli --target "$VOW_TARGET"
  helpers="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
  mkdir -p "$helpers"
  cp "target/$VOW_TARGET/debug/vow" "$helpers/vow"
  # Nested code is signed before the app seals it.
  if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime \
      --identifier "$PRODUCT_BUNDLE_IDENTIFIER.cli" "$helpers/vow"
  fi
fi
