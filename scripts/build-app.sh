#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_FLAGS=(--configuration release)
INSTALL_APP=false
for ARGUMENT in "$@"; do
    case "$ARGUMENT" in
        --universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
        --install) INSTALL_APP=true ;;
        *) printf 'Unknown option: %s\n' "$ARGUMENT" >&2; exit 64 ;;
    esac
done
bash "$PROJECT_ROOT/scripts/swift-tool.sh" build "${BUILD_FLAGS[@]}"
BIN_PATH="$(bash "$PROJECT_ROOT/scripts/swift-tool.sh" build "${BUILD_FLAGS[@]}" --show-bin-path)"
DIST_PATH="$PROJECT_ROOT/dist"
STAGING_PATH="$(mktemp -d "${TMPDIR:-/tmp}/ClearDisplay-stage.XXXXXX")"
LOCAL_APP_PATH="$HOME/Applications/ClearDisplay.app"
ROLLBACK_PATH="$STAGING_PATH/previous-install"
INSTALL_COMMITTED=false
cleanup() {
    RESULT=$?
    # Keep the prior app only during installation, then remove the temporary
    # rollback. Never retain a second indexed .app in the project tree.
    if [[ "$INSTALL_COMMITTED" != true && -d "$ROLLBACK_PATH" ]]; then
        if [[ -e "$LOCAL_APP_PATH" ]]; then rm -rf "$LOCAL_APP_PATH"; fi
        mv "$ROLLBACK_PATH" "$LOCAL_APP_PATH"
    fi
    rm -rf "$STAGING_PATH"
    exit "$RESULT"
}
trap cleanup EXIT
APP_PATH="$STAGING_PATH/ClearDisplay.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Helpers" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/ClearDisplay" "$APP_PATH/Contents/MacOS/ClearDisplay"
cp "$BIN_PATH/DisplayRescue" "$APP_PATH/Contents/Helpers/DisplayRescue"
cp "$BIN_PATH/DisplayVirtualHost" "$APP_PATH/Contents/Helpers/DisplayVirtualHost"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/LICENSE" "$APP_PATH/Contents/Resources/LICENSE.txt"
ICONSET_PATH="$STAGING_PATH/AppIcon.iconset"
mkdir -p "$ICONSET_PATH"
xcrun swift "$PROJECT_ROOT/scripts/generate-icon.swift" "$ICONSET_PATH"
iconutil -c icns "$ICONSET_PATH" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
xattr -cr "$APP_PATH"
codesign --force --sign - --timestamp=none --options runtime "$APP_PATH/Contents/Helpers/DisplayRescue"
codesign --force --sign - --timestamp=none --options runtime "$APP_PATH/Contents/Helpers/DisplayVirtualHost"
codesign --force --sign - --timestamp=none --options runtime "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
mkdir -p "$DIST_PATH"
# Archive while the signed bundle is outside any cloud File Provider directory.
ditto -c -k --norsrc --keepParent "$APP_PATH" "$DIST_PATH/ClearDisplay-0.1.0.zip"
if [[ "$INSTALL_APP" == true ]]; then
    mkdir -p "$HOME/Applications"
    if [[ -e "$LOCAL_APP_PATH" ]]; then
        PRIOR_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$LOCAL_APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "$PRIOR_ID" != "dev.cleardisplay.app" ]]; then
            printf 'Another app already exists at %s\n' "$LOCAL_APP_PATH" >&2
            exit 1
        fi
        mv "$LOCAL_APP_PATH" "$ROLLBACK_PATH"
    fi
    ditto --norsrc --noextattr "$APP_PATH" "$LOCAL_APP_PATH"
    codesign --verify --deep --strict "$LOCAL_APP_PATH"
    INSTALL_COMMITTED=true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$LOCAL_APP_PATH"
    printf 'Installed: %s\n' "$LOCAL_APP_PATH"
fi
# The distributable is ZIP-only. The sole launchable installation lives in
# ~/Applications; staging and temporary rollback are removed by the EXIT trap.
printf 'Packaged: %s\n' "$DIST_PATH/ClearDisplay-0.1.0.zip"
