#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT/MacBar.xcodeproj}"
SCHEME="${SCHEME:-MacBar}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/MacBar-AppStore}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/MacBar.xcarchive}"
PKG_PATH="${PKG_PATH:-$BUILD_ROOT/MacBar-AppStore-Upload.pkg}"
PROFILE_PATH="${PROFILE_PATH:-}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
PROFILE_PLIST="$BUILD_ROOT/profile.plist"
APP_PATH="$ARCHIVE_PATH/Products/Applications/MacBar.app"

cd "$ROOT"

rm -rf "$ARCHIVE_PATH" "$PKG_PATH"
mkdir -p "$BUILD_ROOT"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Missing Xcode project at $PROJECT_PATH" >&2
  exit 1
fi

if [[ -z "$APP_SIGN_IDENTITY" ]]; then
  APP_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Mac App Distribution: [^"]*\)"/\1/p' \
      | head -n 1 || true
  )"
fi

if [[ -z "$APP_SIGN_IDENTITY" ]]; then
  APP_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(3rd Party Mac Developer Application: [^"]*\)"/\1/p' \
      | head -n 1 || true
  )"
fi

if [[ -z "$INSTALLER_SIGN_IDENTITY" ]]; then
  INSTALLER_SIGN_IDENTITY="$(
    security find-certificate -a -c 'Mac Installer Distribution:' -p 2>/dev/null \
      | openssl x509 -subject -noout 2>/dev/null \
      | sed -E -n 's/^subject=.*CN ?= ?(Mac Installer Distribution: .*), OU=.*$/\1/p' \
      | head -n 1 || true
  )"
fi

if [[ -z "$INSTALLER_SIGN_IDENTITY" ]]; then
  INSTALLER_SIGN_IDENTITY="$(
    security find-certificate -a -c '3rd Party Mac Developer Installer:' -p 2>/dev/null \
      | openssl x509 -subject -noout 2>/dev/null \
      | sed -E -n 's/^subject=.*CN ?= ?(3rd Party Mac Developer Installer: .*), OU=.*$/\1/p' \
      | head -n 1 || true
  )"
fi

if [[ -z "$PROFILE_PATH" ]]; then
  while IFS= read -r -d '' candidate; do
    security cms -D -i "$candidate" > "$PROFILE_PLIST"
    app_identifier="$(
      /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST" 2>/dev/null || true
    )"
    if [[ "${app_identifier#*.}" == "app.macbar.macbar" ]]; then
      PROFILE_PATH="$candidate"
      break
    fi
  done < <(
    find "$HOME/Library/MobileDevice/Provisioning Profiles" \
      \( -name '*.provisionprofile' -o -name '*.mobileprovision' \) \
      -type f \
      -print0 2>/dev/null
  )
fi

if [[ -z "$APP_SIGN_IDENTITY" ]]; then
  echo "Missing app signing identity" >&2
  exit 1
fi

if [[ -z "$INSTALLER_SIGN_IDENTITY" ]]; then
  echo "Missing installer signing identity" >&2
  exit 1
fi

if [[ -z "$PROFILE_PATH" || ! -f "$PROFILE_PATH" ]]; then
  echo "Missing provisioning profile for app.macbar.macbar" >&2
  exit 1
fi

security cms -D -i "$PROFILE_PATH" > "$PROFILE_PLIST"

TEAM_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST"
)"
APP_IDENTIFIER="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST"
)"
PROFILE_NAME="$(
  /usr/libexec/PlistBuddy -c 'Print :Name' "$PROFILE_PLIST"
)"
PROFILE_UUID="$(
  /usr/libexec/PlistBuddy -c 'Print :UUID' "$PROFILE_PLIST"
)"

if [[ "${APP_IDENTIFIER#*.}" != "app.macbar.macbar" ]]; then
  echo "Provisioning profile app identifier mismatch: $APP_IDENTIFIER" >&2
  exit 1
fi

xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  PRODUCT_BUNDLE_IDENTIFIER=app.macbar.macbar \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$APP_SIGN_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  PROVISIONING_PROFILE="$PROFILE_UUID" \
  "$@"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archived app not found at $APP_PATH" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

productbuild \
  --component "$APP_PATH" /Applications \
  --sign "$INSTALLER_SIGN_IDENTITY" \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH"

echo "Note: $PKG_PATH is for App Store Connect upload only. Do not install it locally."
echo "Project: $PROJECT_PATH"
echo "Archive: $ARCHIVE_PATH"
echo "App bundle: $APP_PATH"
echo "Provisioning profile: $PROFILE_PATH"
echo "Profile name: $PROFILE_NAME"
echo "App identity: $APP_SIGN_IDENTITY"
echo "Installer identity: $INSTALLER_SIGN_IDENTITY"
echo "Installer package: $PKG_PATH"
