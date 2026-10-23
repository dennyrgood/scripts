#!/bin/bash
# denniss-macbook-air-snapshot-fleet-configs.sh
# Created: 2026-07-21 — snapshots this Mac's rebuild/config state into fleet-configs.
# Manual-run; review `git diff` and commit yourself after.
#
# The fleet writer + metrics server + their LaunchAgent plists are version-controlled
# in the scripts repo (Status/ and launchagents/) — `launchagents/install.sh` recreates
# them — so we do NOT copy those. We capture live state + a pointer for rebuild.

set -e
DEST=~/repos/fleet-configs/DennissMacBookAir
mkdir -p "$DEST"

launchctl list | grep -i com.dennis          > "$DEST/launchctl-com-dennis.txt" || true
ls -1 ~/Library/LaunchAgents/com.dennis.*.plist > "$DEST/installed-launchagents.txt" 2>/dev/null || true
command -v brew >/dev/null 2>&1 && brew leaves > "$DEST/brew-leaves.txt" || true
sw_vers                                        > "$DEST/sw_vers.txt"
[ -f ~/.hammerspoon/init.lua ] && cp ~/.hammerspoon/init.lua "$DEST/init.lua" || true

# README.md is hand-maintained in fleet-configs — this only seeds it on a new box.
# Edit the README there, not this template (which is not kept in sync).
[ -f "$DEST/README.md" ] || cat > "$DEST/README.md" <<'EOF'
# DennissMacBookAir — rebuild notes

Fleet-status role: Mac writer + metrics server (both version-controlled).

Rebuild:
1. Clone the `scripts` repo to `~/repos/scripts`.
2. `cd ~/repos/scripts/launchagents && ./install.sh` — installs mb's LaunchAgents (`MB_AGENTS`
   in that script: the search/travel/comfy GUIs, heartbeat-writer, fleet-metrics-server,
   tmdb-explorer, money-web and money-backup; plists live in `scripts/launchagents/`).
   Not the `mmm-*` agents or comfy-fleet-scan. fleet-digest, mb-health-monitor and
   mb-nightly-summary are not installed by that script.
3. `./tailscale-serve.sh` (this folder) — re-creates the `tailscale serve` entries: Ollama on
   TCP 11434 and money on HTTP 5040 (`http://denniss-macbook-air:5040/`). Needs Tailscale signed in.
4. Metrics writer/server code: `scripts/Status/onedrive_heartbeat_writer_all_macs.py`
   and `scripts/Status/fleet_metrics_server.py`.

Captured here: live `launchctl` state, installed agent list, `brew leaves`, `sw_vers`,
and the Hammerspoon config (`init.lua` — restore to `~/.hammerspoon/init.lua`).
EOF

echo "Snapshot complete. Review: cd $DEST && git status"
