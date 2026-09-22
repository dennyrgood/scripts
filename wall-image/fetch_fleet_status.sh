#!/bin/bash
# fetch_fleet_status.sh -- the ONLY thing in this pipeline allowed to touch
# the network directly under launchd. macOS's Local Network permission for a
# launchd-spawned process is gated on the immediate parent of whatever calls
# curl/opens a socket -- confirmed 2026-09-22 that curl succeeds here (direct
# child of this Apple-signed bash script) but fails when its immediate parent
# is an unsigned Homebrew python3, even with this same trusted bash further
# up the ancestry chain. So: this script is the only network caller, and it
# writes plain JSON to disk; fleet_snapshot_producer.py only ever reads that
# file and does no networking of its own.
set -u
HOST="${FLEET_API_HOST:-192.168.178.158}"
PORT="${FLEET_API_PORT:-5010}"
SECONDS_BETWEEN="${POLL_SECONDS:-15}"
OUT="$(dirname "$0")/inbox/fleet/status.json"

mkdir -p "$(dirname "$OUT")"

echo "[fetch_fleet_status] polling ${HOST}:${PORT} every ${SECONDS_BETWEEN}s -> ${OUT}"
while true; do
    if curl -fsS --max-time 10 "http://${HOST}:${PORT}/api/status" -o "${OUT}.tmp"; then
        mv "${OUT}.tmp" "${OUT}"
    else
        echo "[fetch_fleet_status] curl failed (exit $?)"
        rm -f "${OUT}.tmp"
    fi
    sleep "$SECONDS_BETWEEN"
done
