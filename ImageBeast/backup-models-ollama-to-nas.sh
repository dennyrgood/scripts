#!/usr/bin/env bash
# backup-models-ollama-to-nas.sh
#
# SUPERSEDED 2026-09-18: see backup-comfyui-models-to-nas.sh header -- native
# Windows rsync+OpenSSH cannot talk to FleetNAS's UGOS rsync-backup wrapper.
# Use backup-models-ollama-to-nas-smb.ps1 instead.
#
# One-time backup: OneDrive Models_ollama (ib) -> FleetNAS /volume1/models_backup/Models_ollama
# Priority 3.
#
# Usage:
#   ./backup-models-ollama-to-nas.sh        # dry run (lists what would be copied, copies nothing)
#   ./backup-models-ollama-to-nas.sh go     # actually performs the copy
#
# Pre-check already done: verified 2026-09-18 that all 163 files in this OneDrive
# folder are fully hydrated locally (no OFFLINE / cloud-placeholder attributes),
# so this is a real local copy, not stub files. Re-check if OneDrive has evicted
# files to free space since then:
#   Get-ChildItem -Recurse -File <path> | Where-Object { $_.Attributes -band 0x1000 -or $_.Attributes -band 0x400000 }
#
# See backup-comfyui-models-to-nas.sh for why MSYS_NO_PATHCONV=1 + /cygdrive/c/...
# is required on this box's rsync build.

set -euo pipefail

SRC="/cygdrive/c/Users/Pc/OneDrive/DropBoxReplacement/MathesDropBox/0ComfyUI/Models_ollama/"
DEST="dhm@192.168.178.123:/volume1/misc/models_backup/Models_ollama/"

if [ "${1:-}" = "go" ]; then
  echo ">>> REAL RUN: copying $SRC -> $DEST"
  MSYS_NO_PATHCONV=1 rsync -a --partial --human-readable --info=progress2 --stats \
    -e ssh "$SRC" "$DEST"
else
  echo ">>> DRY RUN (pass 'go' as arg to actually copy): $SRC -> $DEST"
  MSYS_NO_PATHCONV=1 rsync -avn -e ssh "$SRC" "$DEST"
fi
