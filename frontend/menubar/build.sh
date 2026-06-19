#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV_PY="$ROOT/backend/.venv/bin/python3"
if [ ! -x "$VENV_PY" ]; then
  python3 -m venv "$ROOT/backend/.venv"
fi
"$VENV_PY" -m pip install -q --disable-pip-version-check -r "$ROOT/backend/requirements.txt"
REQUESTS_VER="$("$VENV_PY" -c "import requests; print(requests.__version__)" 2>/dev/null || echo FAILED)"

SRC_MAIN="$ROOT/frontend/menubar/JiraAlertMenuBar.swift"
SRC_PANEL="$ROOT/frontend/menubar/MenuPanelView.swift"
RES="$ROOT/frontend/menubar/Resources"
OUT="$ROOT/frontend/menubar/dxFilters.app"
BIN="$OUT/Contents/MacOS/dxFilters"
APP_NAME="dxFilters"
CONFIG_DIR="$HOME/.config/jira-alert"
CONFIG_FILE="$CONFIG_DIR/repo.path"
MASTER="$RES/jntc-logo-master.png"

mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
mkdir -p "$CONFIG_DIR"
echo "$ROOT" > "$CONFIG_FILE"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

if [ ! -f "$MASTER" ]; then
  echo "Missing logo master: $MASTER" >&2
  exit 1
fi

# Raster sizes for menu bar, panel header, notifications, and bundle icon.
sips -z 18 18 "$MASTER" --out "$RES/jntc-logo.png" >/dev/null
sips -z 36 36 "$MASTER" --out "$RES/jntc-logo@2x.png" >/dev/null
sips -z 56 56 "$MASTER" --out "$RES/jntc-logo-panel@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$RES/notification-icon.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$RES/notification-icon@2x.png" >/dev/null

ICONSET="$RES/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$MASTER" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
rm -rf "$ICONSET"

rm -f "$OUT/Contents/Resources/jira-logo.png" \
  "$OUT/Contents/Resources/jira-logo@2x.png" \
  "$OUT/Contents/Resources/jira-logo-panel@2x.png" \
  "$OUT/Contents/Resources/jira-logo.svg"
cp "$RES/jntc-logo.png" "$RES/jntc-logo@2x.png" "$RES/jntc-logo-panel@2x.png" \
  "$RES/notification-icon.png" "$RES/notification-icon@2x.png" "$RES/AppIcon.icns" \
  "$OUT/Contents/Resources/"
if [ -f "$RES/watchers-eye.png" ]; then
  cp "$RES/watchers-eye.png" "$RES/watchers-eye@2x.png" "$OUT/Contents/Resources/"
fi
if [ -f "$RES/alert-notification.mp3" ]; then
  cp "$RES/alert-notification.mp3" "$OUT/Contents/Resources/"
fi

swiftc "$SRC_MAIN" "$SRC_PANEL" \
  -o "$BIN" \
  -framework Cocoa \
  -framework UserNotifications \
  -parse-as-library

# Finder custom-icon / quarantine xattrs break ad-hoc codesign on .app bundles.
strip_bundle_detritus() {
  local bundle="$1"
  xattr -cr "$bundle" 2>/dev/null || true
  find "$bundle" -name $'Icon\r' -delete 2>/dev/null || true
  find "$bundle" -name '._*' -delete 2>/dev/null || true
}

strip_bundle_detritus "$RES"
strip_bundle_detritus "$OUT"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.dxfilters.menubar</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.8</string>
    <key>CFBundleVersion</key>
    <string>12</string>
    <key>JiraAlertRepoRoot</key>
    <string>${ROOT}</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

strip_bundle_detritus "$OUT"
if ! codesign --force --deep --sign - "$OUT"; then
  echo "Warning: codesign failed; stripping xattrs and retrying once." >&2
  strip_bundle_detritus "$OUT"
  codesign --force --deep --sign - "$OUT"
fi

echo "Built: $OUT"
echo "Icons: $OUT/Contents/Resources/jntc-logo*.png"
{
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") build.sh ok ROOT=$ROOT"
  echo "  venv=$VENV_PY requests=$REQUESTS_VER"
} >> "$CONFIG_DIR/dxFilters.log"
echo "Run: open \"$OUT\""
