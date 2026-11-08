#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/seed-pull.sh
# 2026-11-08 — the user's interactive `pull` function from the old `seed` tmux session,
# made into a script, plus one guard: check the archive marker before EVERY attempt.
# 2026-11-08 — generalised for several NAS folders: STOP_AT, RSYNC_EXTRA and a log
# file per folder. Normally called by 9046unix-nightly-pull.sh, not directly.
#
# Why the marker guard: in a power cut the archive drive drops off USB and systemd
# unmounts it, leaving an empty mount-point directory on the root SSD. The router
# usually goes down too, so rsync fails with a network error and this loop retries in
# 5 min. If Wi-Fi is back before the health monitor has remounted the drive (it checks
# every 5 min), an unguarded retry recreates <dest>/<dir>/ on the SSD and starts
# copying the whole tree onto the 455 GB system disk.
#
# No --delete, on purpose: 9046unix is a backup of a backup of a backup, so nothing
# deleted at home (or purged from Immich's trash) is ever removed here. 300 KB/s cap
# always (shared connection).
#
# Usage:  seed-pull.sh <nas-dir> <archive-mount>
#   <nas-dir>       folder on FleetNAS, pulled from dhm@192.168.178.123:/<nas-dir>/
#                   (rsync sees /immich, /photo_legacy, /misc/money; an ssh shell
#                   sees the same folders under /volume1/)
#   <archive-mount> e.g. /mnt/archive01p (must contain .archive-mounted);
#                   files land in <archive-mount>/<nas-dir>/
# Optional environment:
#   STOP_AT=YYYY-MM-DDTHH:MM  stop for the night at that time (rsync --stop-at); the
#                             next run resumes. Exits 0 with "PAUSED", no .ok stamp.
#   RSYNC_EXTRA="..."         extra rsync options (e.g. --backup --backup-dir=... for money)
#   RSYNC_LOG=path            per-file log (default ~/rsync-<nas-dir>.log)
# On success writes ~/.seed-pull-<nas-dir>.ok (epoch), read by the nightly summary.

SRC_DIR="${1:?usage: seed-pull.sh <nas-dir> <archive-mount>}"
DEST="${2:?usage: seed-pull.sh <nas-dir> <archive-mount>}"
KEY="${SRC_DIR//\//_}"
MARKER="$DEST/.archive-mounted"
LOGF="${RSYNC_LOG:-$HOME/rsync-$KEY.log}"

STOP_ARG=""; STOP_EPOCH=""
if [ -n "$STOP_AT" ]; then
    STOP_ARG="--stop-at=$STOP_AT"
    STOP_EPOCH=$(date -d "${STOP_AT/T/ }" +%s)
fi
past_stop() { [ -n "$STOP_EPOCH" ] && [ "$(date +%s)" -ge $(( STOP_EPOCH - 60 )) ]; }

# One copy per folder at a time. flock covers runs of this script (incl. one sleeping
# between retries); pgrep covers an rsync of the same folder started some other way.
exec 9>"/tmp/seed-pull-$KEY.lock"
if ! flock -n 9; then
    echo "$(date) $SRC_DIR: already running (lock held), skipping"; exit 0
fi
if pgrep -f "^rsync .*192\.168\.178\.123:/${SRC_DIR}/" >/dev/null; then
    echo "$(date) $SRC_DIR: an rsync is already running, skipping"; exit 0
fi

for i in $(seq 1 50); do
    if past_stop; then echo "PAUSED $SRC_DIR for tonight (stop time $STOP_AT) $(date)"; exit 0; fi
    if [ ! -f "$MARKER" ]; then
        echo "no $MARKER (drive not mounted?), retry $i in 5 min $(date)"
        sleep 300
        continue
    fi
    # Live progress line only in a terminal; from cron it would just flood the log.
    PROGRESS=""; [ -t 1 ] && PROGRESS="--info=progress2"
    # shellcheck disable=SC2086  # RSYNC_EXTRA / STOP_ARG are deliberately word-split
    rsync -a --partial --bwlimit=300 $PROGRESS $STOP_ARG $RSYNC_EXTRA \
        --compress --compress-choice=zstd --exclude='#recycle' \
        --log-file="$LOGF" \
        "dhm@192.168.178.123:/$SRC_DIR/" "$DEST/$SRC_DIR/"
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ] && past_stop; then
        echo "PAUSED $SRC_DIR for tonight (stop time $STOP_AT, rsync rc=$rc) $(date)"; exit 0
    fi
    case $rc in
        0|24) echo "DONE $SRC_DIR $(date)"
              # 0 also means "nothing left to copy", so this is a seed's finish line too.
              date +%s > "$HOME/.seed-pull-$KEY.ok"
              exit 0 ;;
        10|12|30|35|255) echo "network error $rc on $SRC_DIR, retry $i in 5 min $(date)"; sleep 300 ;;
        *) echo "rsync exit $rc on $SRC_DIR - stopping $(date)"; exit $rc ;;
    esac
done
echo "gave up on $SRC_DIR after 50 attempts $(date)"
exit 1
