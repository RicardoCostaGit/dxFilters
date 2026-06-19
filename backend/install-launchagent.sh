#!/bin/bash
# Generate and install a user LaunchAgent with paths for this machine and repo clone.
set -euo pipefail

BACKEND="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$BACKEND/.." && pwd)"
TEMPLATE="$BACKEND/com.dxfilters.plist.template"
RUNNER="$BACKEND/run-jira-alert.sh"
LABEL="com.dxfilters"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/dxfilters"
GUI_UID="$(id -u)"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Missing template: $TEMPLATE" >&2
  exit 1
fi

chmod +x "$RUNNER"
mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"

escape_sed() {
  printf '%s' "$1" | sed -e 's/[&/\]/\\&/g'
}

RUNNER_ESC="$(escape_sed "$RUNNER")"
ROOT_ESC="$(escape_sed "$ROOT")"
LOG_ESC="$(escape_sed "$LOG_DIR")"

launchctl bootout "gui/${GUI_UID}" "$DEST" 2>/dev/null || true

sed \
  -e "s|@RUNNER@|${RUNNER_ESC}|g" \
  -e "s|@REPO_ROOT@|${ROOT_ESC}|g" \
  -e "s|@LOG_DIR@|${LOG_ESC}|g" \
  "$TEMPLATE" > "$DEST"

launchctl bootstrap "gui/${GUI_UID}" "$DEST"
launchctl enable "gui/${GUI_UID}/${LABEL}" 2>/dev/null || true

echo "Installed LaunchAgent: $DEST"
echo "  Repo:    $ROOT"
echo "  Runner:  $RUNNER"
echo "  Logs:    $LOG_DIR/{out,err}.log"
echo "  Poll:    every 300s (one CLI check per run; no menu bar banners)"
echo ""
echo "Note: CLI checks do not post Notification Center banners. Use dxFilters.app for alerts."
echo "Unload: launchctl bootout gui/${GUI_UID} \"$DEST\""
