#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-nightly-pull.sh
# 2026-11-08 — created. The one nightly job that pulls everything from FleetNAS, in
# order, so only ONE copy uses the shared 300 KB/s link at a time.
# dhm crontab:  @reboot (after 2 min)  and  03:00 daily.
#
#   1. immich        -> /mnt/archive01p   (Immich: originals + DB dumps)
#   2. misc/money    -> /mnt/archive02s   with a versions folder: a file about to be
#                       overwritten is moved first to /mnt/archive02s/misc/.versions/<date>/
#   3. photo_legacy  -> /mnt/archive00p   (frozen, ~838 GB, ~32 days at 300 KB/s).
#                       Only once Immich has completed at least once (user: legacy must
#                       not start before Immich is done). Runs until 02:45, so the next
#                       03:00 run gets Immich + money through first, then resumes it.
#
# A run can last nearly a day; the lock makes an overlapping start (e.g. @reboot and
# 03:00) skip. Each folder also has its own lock in seed-pull.sh.

PULL=/home/dhm/repos/scripts/9046Unix/seed-pull.sh

exec 8>/tmp/9046unix-nightly-pull.lock
if ! flock -n 8; then
    echo "$(date) nightly pull already running, skipping"; exit 0
fi
echo "=== $(date) nightly pull start"

# 1. Immich (keeps its old per-file log name for continuity)
RSYNC_LOG="$HOME/sync-initial.log" "$PULL" immich /mnt/archive01p

# 2. Money, with dated versions of anything replaced
RSYNC_EXTRA="--backup --backup-dir=/mnt/archive02s/misc/.versions/$(date +%F)" \
    "$PULL" misc/money /mnt/archive02s

# 3. photo_legacy, in nightly chunks, only after Immich's first complete run
if [ -f "$HOME/.seed-pull-immich.ok" ]; then
    if [ $((10#$(date +%H%M))) -lt 245 ]; then day=today; else day=tomorrow; fi
    STOP_AT=$(date -d "$day 02:45" +%Y-%m-%dT%H:%M) "$PULL" photo_legacy /mnt/archive00p
else
    echo "$(date) photo_legacy: waiting until Immich has completed once"
fi
echo "=== $(date) nightly pull end"
