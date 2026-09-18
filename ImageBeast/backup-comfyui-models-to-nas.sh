#!/usr/bin/env bash
# backup-comfyui-models-to-nas.sh
#
# SUPERSEDED 2026-09-18: native Windows rsync+OpenSSH cannot talk to FleetNAS's
# UGOS rsync-backup wrapper at all -- confirmed against this script ("dup() in/
# out/err failed" / "connection unexpectedly closed", 0 bytes transferred). This
# is the same failure already documented in AmsterdamDesktop/push_media_to_
# fleetnas.sh (2026-08-04), whose fix was to run rsync from WSL Ubuntu instead
# of native Windows. `ib` has no WSL installed, so use the SMB/robocopy sibling
# script instead: backup-comfyui-models-to-nas-smb.ps1. Left here for reference
# / in case WSL ever gets installed on this box.
#
# One-time backup: C:\ComfyUI_Models (ib) -> FleetNAS /volume1/models_backup/ComfyUI_Models
# Priority 1 (no other existing copy of this dir).
#
# Usage:
#   ./backup-comfyui-models-to-nas.sh        # dry run (lists what would be copied, copies nothing)
#   ./backup-comfyui-models-to-nas.sh go      # actually performs the copy
#
# Notes:
# - Requires MSYS_NO_PATHCONV=1 + /cygdrive/c/... paths: this box's rsync is the
#   cwrsync (Chocolatey) build, whose own cygwin layer needs cygdrive-style paths,
#   while Git Bash's automatic path conversion (if not disabled) rewrites both
#   sides into C:\... form, which rsync then misparses as two remote hosts.
# - Prompts for the dhm@192.168.178.123 SSH password (no key set up yet).
# - Destination base dir /volume1/misc/models_backup must already exist on the
#   NAS (run once: ssh dhm@192.168.178.123 "mkdir -p /volume1/misc/models_backup").
#   /volume1 itself is root-owned (755); /volume1/misc is the writable (+ACL)
#   generic share dhm has access to, confirmed 2026-09-18.

set -euo pipefail

SRC="/cygdrive/c/ComfyUI_Models/"
DEST="dhm@192.168.178.123:/volume1/misc/models_backup/ComfyUI_Models/"

if [ "${1:-}" = "go" ]; then
  echo ">>> REAL RUN: copying $SRC -> $DEST"
  MSYS_NO_PATHCONV=1 rsync -a --partial --human-readable --info=progress2 --stats \
    -e ssh "$SRC" "$DEST"
else
  echo ">>> DRY RUN (pass 'go' as arg to actually copy): $SRC -> $DEST"
  MSYS_NO_PATHCONV=1 rsync -avn -e ssh "$SRC" "$DEST"
fi
