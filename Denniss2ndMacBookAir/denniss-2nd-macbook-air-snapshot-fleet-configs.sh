#!/bin/bash
# denniss-2nd-macbook-air-snapshot-fleet-configs.sh
# Created: 2026-07-21 — snapshots this Mac's rebuild/config state into fleet-configs.
# Manual-run; review `git diff` and commit yourself after.
#
# Fleet writer + metrics server + their LaunchAgent plists are version-controlled in
# the scripts repo (Status/ and launchagents/); `launchagents/install.sh` recreates
# them, so we don't copy those — just capture live state + a rebuild pointer.

set -e
DEST=~/repos/fleet-configs/Denniss2ndMacBookAir
mkdir -p "$DEST"

launchctl list | grep -i com.dennis          > "$DEST/launchctl-com-dennis.txt" || true
ls -1 ~/Library/LaunchAgents/com.dennis.*.plist > "$DEST/installed-launchagents.txt" 2>/dev/null || true
command -v brew >/dev/null 2>&1 && brew leaves > "$DEST/brew-leaves.txt" || true
sw_vers                                        > "$DEST/sw_vers.txt"
[ -f ~/.hammerspoon/init.lua ] && cp ~/.hammerspoon/init.lua "$DEST/init.lua" || true

# README.md is hand-maintained in fleet-configs — this only seeds it on a new box.
# Edit the README there, not this template (which is not kept in sync).
[ -f "$DEST/README.md" ] || cat > "$DEST/README.md" <<'EOF'
# Denniss2ndMacBookAir — rebuild notes

Fleet-status role: Mac writer + metrics server (both version-controlled).

Rebuild:
1. Clone the `scripts` repo to `~/repos/scripts`.
2. `cd ~/repos/scripts/launchagents && ./install.sh`.
3. Writer/server code lives in `scripts/Status/`.

Captured here: live `launchctl` state, installed agent list, `brew leaves`, `sw_vers`,
and the Hammerspoon config (`init.lua` — restore to `~/.hammerspoon/init.lua`).
EOF

echo "Snapshot complete. Review: cd $DEST && git status"
