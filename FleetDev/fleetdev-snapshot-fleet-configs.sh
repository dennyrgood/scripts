#!/bin/bash
# fleetdev-snapshot-fleet-configs.sh
# Created: 2026-09-18 — snapshots this Mac's rebuild/config state into fleet-configs.
# Modeled on DennissMacBookAir/denniss-macbook-air-snapshot-fleet-configs.sh.
# Manual-run; review `git diff` and commit yourself after.
#
# The fleet writer + metrics server + their LaunchAgent plists are version-controlled
# in the scripts repo (Status/ and launchagents/) — `launchagents/install.sh` recreates
# them — so we do NOT copy those. We capture live state + a pointer for rebuild.

set -e
DEST=~/repos/fleet-configs/FleetDev
mkdir -p "$DEST"

launchctl list | grep -i com.dennis          > "$DEST/launchctl-com-dennis.txt" || true
ls -1 ~/Library/LaunchAgents/com.dennis.*.plist > "$DEST/installed-launchagents.txt" 2>/dev/null || true
command -v brew >/dev/null 2>&1 && brew leaves > "$DEST/brew-leaves.txt" || true
sw_vers                                        > "$DEST/sw_vers.txt"

cat > "$DEST/README.md" <<'EOF'
# FleetDev — rebuild notes

FleetDev is a MigrationAssistant clone of DennissMacBookAir (mb), Tailscale identity
corrected to FleetDev. Fleet-status role: Mac writer + metrics server (both
version-controlled), same as mb.

Rebuild:
1. Clone the `scripts` repo to `~/repos/scripts`.
2. `cd ~/repos/scripts/launchagents && ./install.sh` — installs the heartbeat-writer
   and fleet-metrics-server LaunchAgents (plists live in `scripts/launchagents/`).
3. Metrics writer/server code: `scripts/Status/onedrive_heartbeat_writer_all_macs.py`
   and `scripts/Status/fleet_metrics_server.py`.
4. Host-specific health monitor + nightly summary: `scripts/FleetDev/fleetdev-health-monitor.sh`,
   `scripts/FleetDev/fleetdev-nightly-summary.sh`, and their plists
   `com.dennis.fleetdev-health-monitor.plist` / `com.dennis.fleetdev-nightly-summary.plist`,
   version-controlled in `scripts/launchagents/` same as mb's.
   HOST is `fleetdev` (2026-09-18), matching this box's live
   `heartbeat_fleetdev.txt` under `~/fleet_monitor/`.

   Note: on first boot after the MigrationAssistant clone, the heartbeat-writer
   briefly self-identified as `Mac-mini.local` (its pre-clone stock Bonjour name)
   because `onedrive_heartbeat_writer_all_macs.py`'s `HOSTNAME_MAP` had no entry
   for the raw `socket.gethostname()` value `FleetDev` and its Tailscale-DNSName
   fallback hadn't resolved cleanly yet — HOST is cached for the life of that
   process, so it kept writing `heartbeat_Mac-mini.local.txt` until restarted.
   Fixed 2026-09-18 by adding `"FleetDev": "fleetdev"` to `HOSTNAME_MAP` in
   `scripts/Status/onedrive_heartbeat_writer_all_macs.py` and kickstarting
   `com.dennis.heartbeat-writer`. If a future clone/rename repeats this, check
   the live `heartbeat_*.txt` filename under `~/fleet_monitor/` rather than
   trusting `hostname`/`scutil` alone before wiring a new box's scripts to it.

Captured here: live `launchctl` state, installed agent list, `brew leaves`, `sw_vers`.
EOF

echo "Snapshot complete. Review: cd $DEST && git status"
