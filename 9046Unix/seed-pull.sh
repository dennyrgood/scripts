#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/seed-pull.sh
# 2026-11-08 — the user's interactive `pull` function from the `seed` tmux session,
# made into a script, plus one guard: check the archive marker before EVERY attempt.
#
# Why the guard: in a power cut the archive drive drops off USB and systemd unmounts
# it, leaving an empty mount-point directory on the root SSD. The router usually goes
# down too, so rsync fails with a network error and this loop retries in 5 min. If
# Wi-Fi is back before the health monitor has remounted the drive (it checks every
# 5 min), an unguarded retry recreates <dest>/<dir>/ on the SSD and starts copying
# the whole tree onto the 455 GB system disk.
#
# Usage (inside tmux):  ~/repos/scripts/9046Unix/seed-pull.sh immich /mnt/archive01p
#   $1 = directory on FleetNAS (pulled from dhm@192.168.178.123:/$1/)
#   $2 = archive mount point (must contain .archive-mounted)

SRC_DIR="${1:?usage: seed-pull.sh <nas-dir> <archive-mount>}"
DEST="${2:?usage: seed-pull.sh <nas-dir> <archive-mount>}"
MARKER="$DEST/.archive-mounted"

# Also the NIGHTLY job (dhm crontab, 03:00). No --delete, on purpose: 9046unix is a
# backup of a backup of a backup, so nothing deleted at home (or purged from Immich's
# trash) is ever removed here. Same 300 KB/s cap as the seed (shared connection).
#
# One copy at a time. flock covers runs of this script (incl. one sleeping between
# retries); pgrep covers an rsync started some other way, e.g. the original `pull`
# shell function in the `seed` tmux session.
exec 9>"/tmp/seed-pull-${SRC_DIR//\//_}.lock"
if ! flock -n 9; then
    echo "$(date) already running (lock held), skipping"; exit 0
fi
if pgrep -f "^rsync .*192\.168\.178\.123:/${SRC_DIR}/" >/dev/null; then
    echo "$(date) an rsync of /${SRC_DIR}/ is already running (seed?), skipping"; exit 0
fi

for i in $(seq 1 50); do
    if [ ! -f "$MARKER" ]; then
        echo "no $MARKER (drive not mounted?), retry $i in 5 min $(date)"
        sleep 300
        continue
    fi
    # Live progress line only in a terminal; from cron it would just flood the log.
    PROGRESS=""; [ -t 1 ] && PROGRESS="--info=progress2"
    rsync -a --partial --bwlimit=300 $PROGRESS \
        --compress --compress-choice=zstd --exclude='#recycle' \
        --log-file="$HOME/sync-initial.log" \
        "dhm@192.168.178.123:/$SRC_DIR/" "$DEST/$SRC_DIR/"
    rc=$?
    case $rc in
        0|24) echo "DONE $SRC_DIR $(date)"
              # 0 also means "nothing left to copy", so this is the seed's finish line too.
              date +%s > "$HOME/.seed-pull-${SRC_DIR//\//_}.ok"   # read by the nightly summary
              exit 0 ;;
        10|12|30|35|255) echo "network error $rc on $SRC_DIR, retry $i in 5 min $(date)"; sleep 300 ;;
        *) echo "rsync exit $rc on $SRC_DIR - stopping $(date)"; exit $rc ;;
    esac
done
echo "gave up after 50 attempts $(date)"
exit 1
