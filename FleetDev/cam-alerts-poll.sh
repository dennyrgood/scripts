#!/bin/bash
# cam-alerts-poll.sh -- Created: 2026-11-08 17:45 UTC
# Pull room-camera captures from 9046unix (fd pulls only; 9046unix has no login to fd)
# and alert on each new .mp4 ("light ON"): an iMessage text via notify-me, plus an
# email with the snapshot + clip attached (iMessage attachments don't work on this Mac).
# "Still on" .jpg-only captures are pulled and saved but never alerted.
# Run by launchd every 60s: com.dennis.cam-alerts. Log: ~/Library/Logs/cam_alerts.log
# Edit log:
#   2026-11-08 17:45 UTC  created.
#   2026-11-08 18:35 UTC  attachments go by email (notify-me --attach); notify-me exit 3
#                         (text sent, mail failed) counts as sent, so no retry/text loop.
#
# Remote capture names are <%Y-%m-%d_%H%M%S> in 9046unix local time (America/New_York).
# Events are keyed on the .mp4 (the clip takes ~10s to record, so a .jpg can briefly
# exist without its .mp4). Files younger than 30s on 9046unix are not pulled, so a
# clip is never grabbed half-written. Nothing is ever deleted or changed on 9046unix.
# Sent-list: ~/.local/state/cam-alerts.sent (one timestamp per line) -- survives reboots.
# First run (no sent-list): pulls, then marks existing clips sent WITHOUT messaging.

set -u

REMOTE="dhm@9046unix"
RDIR="/mnt/data/cam"
LOCAL="$HOME/cam/9046unix"
STATE="$HOME/.local/state/cam-alerts.sent"
UPFILE="$HOME/.local/state/cam-alerts.up"
NOTIFY="$HOME/repos/scripts/FleetDev/notify-me"
LOCK="/tmp/cam-alerts.lock.d"
MAXSEND=5                       # more unsent events than this -> one summary message
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=2"

log() { echo "$(date -u '+%Y-%m-%d %H:%M:%S UTC') cam-alerts: $*"; }

mkdir -p "$LOCAL" "$HOME/.local/state"

# One run at a time (no flock on macOS). A lock older than 10 min is a crashed run.
[ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# --- 1. what is new (>=30s old, last 7 days) ---------------------------------
LIST=$(mktemp "${TMPDIR:-/tmp}/cam-alerts.XXXXXX")
trap 'rm -f "$LIST"; rmdir "$LOCK" 2>/dev/null' EXIT
if ! $SSH "$REMOTE" "cd $RDIR && find . -type f \( -name '*.jpg' -o -name '*.mp4' \) -mtime -7 -mmin +0.5 -printf '%P\n' | sort" > "$LIST" 2>/dev/null; then
    # Unreachable: stay quiet, retry next poll. Log only the up->down transition.
    if [ "$(cat "$UPFILE" 2>/dev/null)" != "down" ]; then log "9046unix unreachable (will retry quietly)"; echo down > "$UPFILE"; fi
    exit 0
fi
if [ "$(cat "$UPFILE" 2>/dev/null)" = "down" ]; then log "9046unix reachable again"; fi
echo up > "$UPFILE"

# --- 2. pull only new files, gently -----------------------------------------
if [ -s "$LIST" ]; then
    rsync -a --ignore-existing --bwlimit=200 --timeout=60 --files-from="$LIST" \
        -e "$SSH" "$REMOTE:$RDIR/" "$LOCAL/" >/dev/null 2>&1 || { log "rsync failed rc=$? (will retry)"; exit 0; }
fi

# --- 3. first run: seed sent-list, send nothing -----------------------------
if [ ! -f "$STATE" ]; then
    : > "$STATE"
    for m in "$LOCAL"/*/*.mp4; do [ -f "$m" ] && basename "$m" .mp4 >> "$STATE"; done
    log "first run: marked $(wc -l < "$STATE" | tr -d ' ') existing clip(s) as already sent, no messages"
    exit 0
fi

# --- 4. unsent light-ON events (oldest first) -------------------------------
NEW=()
for m in "$LOCAL"/*/*.mp4; do
    [ -f "$m" ] || continue
    ts=$(basename "$m" .mp4)
    grep -qx "$ts" "$STATE" || NEW+=("$m")
done
[ ${#NEW[@]} -gt 0 ] || exit 0

send_one() {   # $1 = mp4 path, $2 = message prefix
    local mp4="$1" ts jpg when out nrc
    ts=$(basename "$mp4" .mp4); jpg="${mp4%.mp4}.jpg"
    when="${ts%%_*} ${ts##*_}"; when="${when:0:10} ${when:11:2}:${when:13:2}:${when:15:2}"
    local args=()
    [ -f "$jpg" ] && args+=(--attach "$jpg")
    args+=(--attach "$mp4")
    out=$("$NOTIFY" ${args[@]+"${args[@]}"} "$2Room cam: light ON at $when (9046unix time). Snapshot + clip emailed to dennyrgood@yahoo.com" 2>&1)
    nrc=$?
    case $nrc in
        0) log "alerted $ts" ;;
        3) log "alerted $ts (text sent; attachment email FAILED, not retried): $out" ;;
        *) log "notify-me failed for $ts rc=$nrc: $out"; return 1 ;;
    esac
}

if [ ${#NEW[@]} -gt "$MAXSEND" ]; then
    last="${NEW[${#NEW[@]}-1]}"
    send_one "$last" "(${#NEW[@]} events since last check; latest) " || exit 0
    for m in "${NEW[@]}"; do basename "$m" .mp4 >> "$STATE"; done
else
    for m in "${NEW[@]}"; do
        send_one "$m" "" || exit 0          # leave unsent; retried next poll
        basename "$m" .mp4 >> "$STATE"
    done
fi
