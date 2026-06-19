#!/bin/bash
# Run jira_alert.py from this repo. Paths are resolved from the script location.
set -euo pipefail

BACKEND="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$BACKEND/.." && pwd)"
cd "$ROOT"

if [[ -x "$BACKEND/.venv/bin/python" ]]; then
  PYTHON="$BACKEND/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
else
  echo "python3 not found (create backend/.venv or install Python 3)" >&2
  exit 127
fi

exec "$PYTHON" "$BACKEND/jira_alert.py" "$@"
