#!/usr/bin/env bash
# linux_metrics_setup.sh — set up the fleet heartbeat writer (cron, every 2 min)
# and fleet_metrics_server (systemd, :9100) on a Linux box, the way 9046unix,
# wbu and cwhu run them. Stdlib-only Python; safe to re-run.
# Created: 2026-11-18 UTC — for pi400 (spuiraspberry).
# Usage (on the box, from a clone at ~/repos/scripts):
#   Status/linux_metrics_setup.sh <tailscale-hostname>
set -euo pipefail

HOST="${1:?usage: linux_metrics_setup.sh <tailscale-hostname>}"
STATUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_NAME="$(id -un)"
OUT_DIR="$HOME/fleet_monitor"
mkdir -p "$OUT_DIR/$HOST"

# 1. Heartbeat writer — one run now, then cron every 2 min.
"$STATUS_DIR/run_heartbeat.sh" "$HOST"
CRON="*/2 * * * * $STATUS_DIR/run_heartbeat.sh $HOST >> $OUT_DIR/$HOST/cron.log 2>&1"
( crontab -l 2>/dev/null | grep -v 'run_heartbeat.sh' || true; echo "$CRON" ) | crontab -
echo "cron: $CRON"

# 2. Metrics server — systemd unit serving ~/fleet_monitor on :9100.
sudo tee /etc/systemd/system/fleet_metrics_server.service >/dev/null <<EOF
[Unit]
Description=Fleet metrics server (serves ~/fleet_monitor over Tailscale)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/python3 $STATUS_DIR/fleet_metrics_server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now fleet_metrics_server
sleep 2
curl -sf "http://localhost:9100/heartbeat_$HOST.txt" && echo "OK: :9100 serving heartbeat_$HOST.txt"
