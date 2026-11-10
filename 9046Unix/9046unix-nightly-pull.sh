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
# 2026-11-10 — one shared GIVEUP_AT (next 02:50) for every folder: during a long
# FleetNAS outage Immich retries until then, and money / photo_legacy each get one
# try, so this run is over before the next 03:00 start.

PULL=/home/dhm/repos/scripts/9046Unix/seed-pull.sh
if [ $((10#$(date +%H%M))) -lt 250 ]; then gday=today; else gday=tomorrow; fi
GIVEUP_AT=$(date -d "$gday 02:50" +%Y-%m-%dT%H:%M)
export GIVEUP_AT

exec 8>/tmp/9046unix-nightly-pull.lock
if ! flock -n 8; then
    echo "$(date) nightly pull already running, skipping"; exit 0
fi
echo "=== $(date) nightly pull start"

# 1. Immich (keeps its old per-file log name for continuity).
#    images/backups/ is excluded (2026-11-08): Immich's own nightly DB backups, a
#    duplicate of postgres-dumps/ that would add ~0.6 GB of new files every night.
RSYNC_LOG="$HOME/sync-initial.log" RSYNC_EXTRA="--exclude=/images/backups/" \
    "$PULL" immich /mnt/archive01p

# 1b. Prune rotating database dumps on 01p (2026-11-08). The NAS writes a new,
#     differently named dump every night and deletes old ones; with no --delete,
#     9046unix would keep every one (~2.8 GB/day, ~1 TB/year). Keep 14 days, but
#     ALWAYS the newest 3 per folder, so a stalled dump job at home never leaves
#     this copy with none. Only these two folders, only *.sql / *.sql.gz files —
#     photos are never touched. images/backups/ is no longer copied (see above),
#     so what the seed already brought over ages out here down to the newest 3.
if [ -f /mnt/archive01p/.archive-mounted ]; then
    for d in /mnt/archive01p/immich/postgres-dumps /mnt/archive01p/immich/images/backups; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.sql.gz' \) -printf '%T@ %p\n' \
            | sort -rn | tail -n +4 | cut -d' ' -f2- \
            | while read -r f; do
                if [ -n "$(find "$f" -mtime +14)" ]; then
                    rm -f -- "$f" && echo "$(date) pruned old dump ${f#/mnt/archive01p/}"
                fi
            done
    done
fi

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
