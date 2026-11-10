#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/seed-pull.sh
# 2026-11-08 — the user's interactive `pull` function from the old `seed` tmux session,
# made into a script, plus one guard: check the archive marker before EVERY attempt.
# 2026-11-08 — generalised for several NAS folders: STOP_AT, RSYNC_EXTRA and a log
# file per folder. Normally called by 9046unix-nightly-pull.sh, not directly.
# 2026-11-09 02:59 UTC — added BatchMode/ConnectTimeout to rsync's ssh (never wait on a
# password prompt; fail fast into the retry).
# 2026-11-10 — network failures retry until a deadline (GIVEUP_AT, default the next
# 02:50, just before the 03:00 run) instead of 50 x 5 min: a ~9 h Amsterdam outage on
# 2026-11-09 outlasted the old 4 h window. Backoff 5 min for the first hour, then 30.
# A port-22 probe runs before each rsync; while FleetNAS is unreachable
# ~/.nas-unreachable-since (epoch) exists, for the nightly summary.
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
#   GIVEUP_AT=YYYY-MM-DDTHH:MM  stop retrying network failures then (default: next 02:50).
#                             At least one attempt is always made.
#   NAS=host                  FleetNAS address (default 192.168.178.123; for testing)
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
NAS="${NAS:-192.168.178.123}"
DOWN_FILE="$HOME/.nas-unreachable-since"
if [ -z "$GIVEUP_AT" ]; then
    if [ $((10#$(date +%H%M))) -lt 250 ]; then day=today; else day=tomorrow; fi
    GIVEUP_AT=$(date -d "$day 02:50" +%Y-%m-%dT%H:%M)
fi
GIVEUP_EPOCH=$(date -d "${GIVEUP_AT/T/ }" +%s)

past_stop() { [ -n "$STOP_EPOCH" ] && [ "$(date +%s)" -ge $(( STOP_EPOCH - 60 )) ]; }

# One copy per folder at a time. flock covers runs of this script (incl. one sleeping
# between retries); pgrep covers an rsync of the same folder started some other way.
exec 9>"/tmp/seed-pull-$KEY.lock"
if ! flock -n 9; then
    echo "$(date) $SRC_DIR: already running (lock held), skipping"; exit 0
fi
if pgrep -f "^rsync .*${NAS//./\\.}:/${SRC_DIR}/" >/dev/null; then
    echo "$(date) $SRC_DIR: an rsync is already running, skipping"; exit 0
fi

# Sleep before the next retry: 5 min for the first hour of failures, then 30 min,
# never past the give-up time. Returns 1 (no sleep) once that time has passed.
wait_retry() {  # <why>
    local now delay
    now=$(date +%s)
    [ "$now" -ge "$GIVEUP_EPOCH" ] && return 1
    delay=300; [ $(( now - FIRST_FAIL )) -ge 3600 ] && delay=1800
    [ $(( now + delay )) -gt "$GIVEUP_EPOCH" ] && delay=$(( GIVEUP_EPOCH - now ))
    echo "$1, retry $i in $((delay / 60)) min (failing for $(( (now - FIRST_FAIL) / 60 )) min, give up at $GIVEUP_AT) $(date)"
    sleep "$delay"
}

i=0; FIRST_FAIL=""
while :; do
    i=$((i + 1))
    if past_stop; then echo "PAUSED $SRC_DIR for tonight (stop time $STOP_AT) $(date)"; exit 0; fi
    if [ ! -f "$MARKER" ]; then
        : "${FIRST_FAIL:=$(date +%s)}"
        wait_retry "no $MARKER (drive not mounted?)" && continue
        break
    fi
    if ! nc -z -w 10 "$NAS" 22 2>/dev/null; then
        : "${FIRST_FAIL:=$(date +%s)}"
        [ -f "$DOWN_FILE" ] || date +%s > "$DOWN_FILE"
        wait_retry "FleetNAS $NAS:22 unreachable since $(date -d "@$(cat "$DOWN_FILE")" '+%a %H:%M')" && continue
        break
    fi
    rm -f "$DOWN_FILE"
    # Live progress line only in a terminal; from cron it would just flood the log.
    PROGRESS=""; [ -t 1 ] && PROGRESS="--info=progress2"
    # shellcheck disable=SC2086  # RSYNC_EXTRA / STOP_ARG are deliberately word-split
    rsync -a --partial --bwlimit=300 $PROGRESS $STOP_ARG $RSYNC_EXTRA \
        --compress --compress-choice=zstd --exclude='#recycle' \
        -e "ssh -o BatchMode=yes -o ConnectTimeout=30" \
        --log-file="$LOGF" \
        "dhm@$NAS:/$SRC_DIR/" "$DEST/$SRC_DIR/"
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ] && past_stop; then
        echo "PAUSED $SRC_DIR for tonight (stop time $STOP_AT, rsync rc=$rc) $(date)"; exit 0
    fi
    case $rc in
        0|24) echo "DONE $SRC_DIR $(date)"
              # 0 also means "nothing left to copy", so this is a seed's finish line too.
              date +%s > "$HOME/.seed-pull-$KEY.ok"
              exit 0 ;;
        10|12|30|35|255)
              : "${FIRST_FAIL:=$(date +%s)}"
              wait_retry "network error $rc on $SRC_DIR" && continue
              break ;;
        *) echo "rsync exit $rc on $SRC_DIR - stopping $(date)"; exit $rc ;;
    esac
done
echo "gave up on $SRC_DIR at $GIVEUP_AT after $i attempts $(date)"
exit 1
