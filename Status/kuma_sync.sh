#!/usr/bin/env bash
# kuma_sync.sh — run kuma_sync.py in its own venv (created on first run).
# Usage: Status/kuma_sync.sh [--dry-run] [--skip-lan] [--url URL] [--user USER]
set -euo pipefail
VENV="$HOME/.venvs/kuma"
if [ ! -x "$VENV/bin/pip" ]; then
  # Rebuild if missing or half-made (e.g. a prior run before python3-venv
  # was installed left python but no pip).
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet uptime-kuma-api-v2
fi
exec "$VENV/bin/python" "$(dirname "$0")/kuma_sync.py" "$@"
