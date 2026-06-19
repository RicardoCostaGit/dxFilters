#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$HOME/Applications/dxFilters.app"
BUILD_APP="$ROOT/frontend/menubar/dxFilters.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT/frontend/menubar/build.sh"
osascript -e 'tell application "dxFilters" to quit' 2>/dev/null || true
osascript -e 'tell application "JNTC" to quit' 2>/dev/null || true
osascript -e 'tell application "Jira Alert" to quit' 2>/dev/null || true
pkill -x "dxFilters" 2>/dev/null || true
pkill -x "JNTC" 2>/dev/null || true
pkill -x "Jira Alert" 2>/dev/null || true
rm -rf "$HOME/Applications/dxFilters.app" "$HOME/Applications/JNTC.app" "$HOME/Applications/Jira Alert.app"
ditto "$BUILD_APP" "$APP"
touch "$APP"

# Write the icon into the bundle so Launch Services and Notification Center pick it up.
swift - <<'SWIFT'
import AppKit

let appPath = NSHomeDirectory() + "/Applications/dxFilters.app"
let icnsPath = appPath + "/Contents/Resources/AppIcon.icns"
guard let icon = NSImage(contentsOfFile: icnsPath) else {
    fputs("Could not load AppIcon.icns\n", stderr)
    exit(1)
}
icon.isTemplate = false
NSWorkspace.shared.setIcon(icon, forFile: appPath, options: [])
SWIFT

"$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true

echo "Installed to $APP"
echo "Registered app icon with Launch Services."
echo "If System Settings still shows the old icon, toggle dxFilters off/on under Notifications."
echo "Opening dxFilters — allow notifications when prompted."
open "$APP"
