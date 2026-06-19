#!/usr/bin/env bash
# ponytail: one runnable check for fresh-install backend + PAT path
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VENV_PY="$ROOT/backend/.venv/bin/python3"
if [ ! -x "$VENV_PY" ]; then
  python3 -m venv "$ROOT/backend/.venv"
fi
"$VENV_PY" -m pip install -q --disable-pip-version-check -r backend/requirements.txt

echo "==> backend tests (venv bootstrap + PAT save + no ModuleNotFoundError)"
"$VENV_PY" -m unittest discover -s backend -p 'test_*.py' -v

echo "smoke-test: ok"
