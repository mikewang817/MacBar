#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${SCHEME:-MacBar}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/MacBar-AppStore}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/MacBar.xcarchive}"
APP_PATH="${APP_PATH:-$BUILD_ROOT/MacBar.app}"
PKG_PATH="${PKG_PATH:-$BUILD_ROOT/MacBar-AppStore-Upload.pkg}"
PROFILE_PATH="${PROFILE_PATH:-}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
CONTENTS_DIR="$APP_PATH/Contents"
PROFILE_PLIST="$BUILD_ROOT/profile.plist"
APP_ENTITLEMENTS_PATH="$BUILD_ROOT/MacBar.app.entitlements"

cd "$ROOT"

rm -rf "$ARCHIVE_PATH" "$APP_PATH" "$PKG_PATH"
mkdir -p "$BUILD_ROOT"

if [[ -z "$APP_SIGN_IDENTITY" ]]; then
  APP_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(3rd Party Mac Developer Application: [^"]*\)"/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$INSTALLER_SIGN_IDENTITY" ]]; then
  INSTALLER_SIGN_IDENTITY="$(
    security find-certificate -a -c '3rd Party Mac Developer Installer:' -p 2>/dev/null \
      | openssl x509 -subject -noout 2>/dev/null \
      | sed -E -n 's/^subject=.*CN ?= ?(3rd Party Mac Developer Installer: .*), OU=.*$/\1/p' \
      | head -n 1
  )"
fi

if [[ -z "$PROFILE_PATH" ]]; then
  while IFS= read -r -d '' candidate; do
    security cms -D -i "$candidate" > "$PROFILE_PLIST"
    app_identifier="$(
      /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST" 2>/dev/null || true
    )"
    if [[ "$app_identifier" == "P69755L5ZN.app.macbar.macbar" ]]; then
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
KEYCHAIN_GROUP="$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:keychain-access-groups:0' "$PROFILE_PLIST" 2>/dev/null || true
)"

cat > "$APP_ENTITLEMENTS_PATH" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" "$APP_ENTITLEMENTS_PATH"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$APP_ENTITLEMENTS_PATH"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.app-sandbox bool true" "$APP_ENTITLEMENTS_PATH"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.files.bookmarks.app-scope bool true" "$APP_ENTITLEMENTS_PATH"
/usr/libexec/PlistBuddy -c "Add :com.apple.security.files.user-selected.read-only bool true" "$APP_ENTITLEMENTS_PATH"

if [[ -n "$KEYCHAIN_GROUP" ]]; then
  /usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" "$APP_ENTITLEMENTS_PATH"
  /usr/libexec/PlistBuddy -c "Add :keychain-access-groups:0 string $KEYCHAIN_GROUP" "$APP_ENTITLEMENTS_PATH"
fi

xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  PRODUCT_BUNDLE_IDENTIFIER=app.macbar.macbar \
  CODE_SIGN_ENTITLEMENTS=MacBar.entitlements \
  CODE_SIGNING_ALLOWED=NO \
  "$@"

RESOURCE_BUNDLE=""
while IFS= read -r -d '' candidate; do
  if [[ -z "$RESOURCE_BUNDLE" || "$candidate" -nt "$RESOURCE_BUNDLE" ]]; then
    RESOURCE_BUNDLE="$candidate"
  fi
done < <(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    \( \
      -path '*/ArchiveIntermediates/MacBar/IntermediateBuildFilesPath/UninstalledProducts/macosx/MacBar_MacBar.bundle' \
      -o \
      -path '*/ArchiveIntermediates/MacBar/BuildProductsPath/Release/MacBar_MacBar.bundle' \
    \) \
    -type d \
    -print0
)

if [[ -z "$RESOURCE_BUNDLE" ]]; then
  echo "Failed to locate MacBar_MacBar.bundle in DerivedData" >&2
  exit 1
fi

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"

cp "$ARCHIVE_PATH/Products/usr/local/bin/MacBar" "$CONTENTS_DIR/MacOS/MacBar"
cp "$ROOT/Sources/MacBar/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROFILE_PATH" "$CONTENTS_DIR/embedded.provisionprofile"

xcrun actool \
  --compile "$CONTENTS_DIR/Resources" \
  --output-format human-readable-text \
  --notices \
  --warnings \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /tmp/macbar_app_store_actool.plist \
  "$ROOT/Sources/MacBar/Resources/Assets.xcassets"

ditto "$RESOURCE_BUNDLE" "$CONTENTS_DIR/Resources/MacBar_MacBar.bundle"

codesign --force --sign "$APP_SIGN_IDENTITY" "$CONTENTS_DIR/Resources/MacBar_MacBar.bundle"
codesign --force --sign "$APP_SIGN_IDENTITY" --entitlements "$APP_ENTITLEMENTS_PATH" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

productbuild \
  --component "$APP_PATH" /Applications \
  --sign "$INSTALLER_SIGN_IDENTITY" \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH"

echo "Note: $PKG_PATH is for App Store Connect upload only. Do not install it locally."
echo "Archive: $ARCHIVE_PATH"
echo "App bundle: $APP_PATH"
echo "Provisioning profile: $PROFILE_PATH"
echo "App identity: $APP_SIGN_IDENTITY"
echo "Installer identity: $INSTALLER_SIGN_IDENTITY"
echo "Installer package: $PKG_PATH"
