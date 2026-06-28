#!/bin/bash
# run_heartbeat.sh — fleet heartbeat writer + rsync wrapper (Linux)
# Created: 2026-06-28 UTC — cron target for WorkBenchUnix and ChatWorkhorseUnix.
# Usage: run_heartbeat.sh <tailscale-hostname>

set -euo pipefail

HOST="${1:?usage: run_heartbeat.sh <hostname>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="/home/dhm/fleet_monitor/${HOST}"
SSH_KEY="/home/dhm/.ssh/id_ed25519_amsterdamdesktop"
RSYNC_DEST="drden@amsterdamdesktop:/cygdrive/d/OneDrive/_sync_monitor/${HOST}/"

python3 "${SCRIPT_DIR}/heartbeat_writer_linux.py" \
    --host "${HOST}" \
    --output-dir "${LOCAL_DIR}"

rsync -a \
    -e "ssh -i ${SSH_KEY} -o BatchMode=yes -o ConnectTimeout=10" \
    "${LOCAL_DIR}/" \
    "${RSYNC_DEST}"
