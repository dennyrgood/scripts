#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-nightly-summary.sh
# 2026-11-08 — created, same shape as ChatWorkhorseUnix/cwhu-nightly-summary.sh.
#
# Nightly health summary for the 9046unix archive server. Runs from ROOT's crontab
# (msmtp config is root-only; smartctl needs root) at 01:00 America/New_York, which is
# 07:00 in Amsterdam, alongside the other boxes' summaries.
#
# Subject format is parsed by Status/fleet_digest.py (EXPECTED_HOSTS has "9046unix"):
#   <✅|⚠️> 9046unix nightly YYYY-MM-DD — <reason>
# Only the FIRST failing check reaches the subject (REASON is set once, later checks
# are guarded on it still being "all healthy"); every check still shows in the TLDR.

TO="dennyrgood@yahoo.com"
CC="dennis.mathes@icloud.com"     # self-CC feeds fleet_digest.py (reads that INBOX)
MONITOR_STATE="/var/tmp/9046unix-monitor-state.tmp"
REMOUNT_LOG="/var/log/9046unix-remount.log"
READSCAN_LOG="/var/log/9046unix-readscan.log"
HEARTBEAT="/home/dhm/fleet_monitor/heartbeat_9046unix.txt"
ARCHIVES=(archive00p archive01p archive02s)
MARKER=".archive-mounted"
# by-id paths: sdX letters shuffle between boots. 02s has no SMART (enclosure).
declare -A SMART_DEV=(
    [archive00p]="/dev/disk/by-id/usb-ASMedia_ASM1156_AAAABBBB0490-0:0"
    [archive01p]="/dev/disk/by-id/usb-ASMedia_ASM1156_AAAABBBB0490-0:1"
)
NOW=$(date +%s)

REASON="all healthy"
fail() { [ "$REASON" = "all healthy" ] && REASON="$1"; }
fmt_age() {
    local s=$1
    if   [ "$s" -lt 3600 ];   then echo "$((s / 60))m"
    elif [ "$s" -lt 172800 ]; then echo "$((s / 3600))h"
    else echo "$((s / 86400))d"; fi
}

TLDR=""
BODY=""

# --- Health monitor freshness + active alerts ---
if [ -f "$MONITOR_STATE" ]; then
    AGE=$(( NOW - $(stat -c %Y "$MONITOR_STATE") ))
    if [ "$AGE" -gt 600 ]; then
        TLDR+="⚠️  health-monitor: stale (last run $(fmt_age $AGE) ago)\n"; fail "health monitor stale"
    else
        TLDR+="  health-monitor: last run $(fmt_age $AGE) ago ✓\n"
    fi
    ACTIVE=$(grep '_ACTIVE=1$' "$MONITOR_STATE" | sed 's/_ACTIVE=1$//' | tr '\n' ' ')
    if [ -n "$ACTIVE" ]; then
        TLDR+="⚠️  health-monitor: ACTIVE ALERTS: ${ACTIVE}\n"; fail "active alerts: ${ACTIVE% }"
    else
        TLDR+="  health-monitor: no active alerts ✓\n"
    fi
else
    TLDR+="⚠️  health-monitor: state file missing (never ran?)\n"; fail "health monitor missing"
fi

# --- Archives: mounted, marked, space, ext4 errors ---
BODY+="=== ARCHIVES ===\n"
for a in "${ARCHIVES[@]}"; do
    mp="/mnt/$a"
    if ! mountpoint -q "$mp"; then
        TLDR+="⚠️  $a: NOT MOUNTED\n"; fail "$a not mounted"; continue
    fi
    if [ ! -f "$mp/$MARKER" ]; then
        TLDR+="⚠️  $a: marker missing\n"; fail "$a marker missing"
    fi
    dev=$(findmnt -no SOURCE "$mp")
    errs=$(cat "/sys/fs/ext4/$(basename "$dev")/errors_count" 2>/dev/null || echo "?")
    use=$(df -h --output=used,avail,pcent "$mp" | tail -1 | awk '{print $1" used, "$2" free ("$3")"}')
    line="  $a ($dev): $use, ext4 errors=$errs"
    if [ "$errs" != "0" ]; then TLDR+="⚠️${line}\n"; fail "$a ext4 errors"; else TLDR+="${line} ✓\n"; fi
    BODY+="$(df -h "$mp" | tail -1)\n"
done
BODY+="\n"

# --- Immich backup to 01p (seed-pull.sh, dhm crontab @reboot + 03:00) ---
# Progress = bytes under /mnt/archive01p/immich vs. the source on FleetNAS
# (/volume1/immich over dhm's ssh key; the rsync path /immich/ maps to it).
# One row per night in PROGRESS_TSV gives the 24h growth and a rough ETA.
# "Copy in progress" is OK during the seed; once a run has completed, the warning
# is: no completed run in 3 days.
PULL_OK="/home/dhm/.seed-pull-immich.ok"
PROGRESS_TSV="/var/lib/9046unix/immich-progress.tsv"
SYNC_FILELOG="/home/dhm/sync-initial.log"
mkdir -p "$(dirname "$PROGRESS_TSV")"
GB() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1e9}'; }
DST_B=$(du -sb /mnt/archive01p/immich 2>/dev/null | awk '{print $1}')
SRC_B=$(timeout 300 sudo -u dhm ssh -o BatchMode=yes -o ConnectTimeout=20 dhm@192.168.178.123 \
        "du -sb --exclude='#recycle' /volume1/immich" 2>/dev/null | awk '{print $1}')
PREV_B=$(tail -1 "$PROGRESS_TSV" 2>/dev/null | awk '{print $2}')
PREV_T=$(tail -1 "$PROGRESS_TSV" 2>/dev/null | awk '{print $1}')
[ -n "$DST_B" ] && printf '%s\t%s\t%s\n' "$NOW" "$DST_B" "${SRC_B:-}" >> "$PROGRESS_TSV"

SIZE="$(GB "${DST_B:-0}") GB"
if [ -n "$SRC_B" ] && [ "$SRC_B" -gt 0 ]; then
    PCT=$(awk -v d="${DST_B:-0}" -v s="$SRC_B" 'BEGIN{p=100*d/s; if(p>100)p=100; printf "%d", p}')
    SIZE="$(GB "${DST_B:-0}") of $(GB "$SRC_B") GB (${PCT}%)"
fi
DELTA=""; ETA=""
if [ -n "$PREV_B" ] && [ -n "$DST_B" ] && [ -n "$PREV_T" ] && [ $(( NOW - PREV_T )) -gt 3600 ]; then
    D=$(( DST_B - PREV_B )); HRS=$(( (NOW - PREV_T) / 3600 ))
    DELTA=", +$(GB $D) GB in ${HRS}h"
    if [ -n "$SRC_B" ] && [ "$D" -gt 0 ] && [ "$SRC_B" -gt "$DST_B" ]; then
        ETA=$(awk -v r="$(( SRC_B - DST_B ))" -v d="$D" -v h="$HRS" 'BEGIN{printf ", ~%.1f days to go", (r/d)*h/24}')
    fi
fi
NEWFILES=$(awk -v s="$(date -d '24 hours ago' '+%Y/%m/%d %H:%M:%S')" \
    '($1" "$2) >= s && $4 ~ /^>f/' "$SYNC_FILELOG" 2>/dev/null | wc -l)

if pgrep -f '^rsync .*192\.168\.178\.123:/immich/' >/dev/null; then
    TLDR+="  immich -> 01p: copying, ${SIZE}${DELTA}${ETA} ✓\n"
elif [ -f "$PULL_OK" ]; then
    PA=$(( NOW - $(cat "$PULL_OK") ))
    line="immich -> 01p: ${SIZE}, last complete run $(fmt_age $PA) ago, ${NEWFILES} files copied in 24h"
    if [ "$PA" -gt 259200 ]; then   # 3 days
        TLDR+="⚠️  ${line}\n"; fail "immich backup stale"
    else
        TLDR+="  ${line} ✓\n"
    fi
else
    TLDR+="⚠️  immich -> 01p: not running and never completed (${SIZE})\n"; fail "immich backup not running"
fi
BODY+="=== IMMICH -> 01p (last 3 runs, ~/immich-pull.log) ===\n$(grep -E 'DONE|error|stopping|skipping|gave up|no .*marker' /home/dhm/immich-pull.log 2>/dev/null | tail -3)\n\n"

# --- SMART (00p, 01p) ---
BODY+="=== SMART ===\n"
for a in archive00p archive01p; do
    d="${SMART_DEV[$a]}"
    if [ ! -e "$d" ]; then TLDR+="⚠️  smart $a: device not present\n"; fail "$a not present"; continue; fi
    OUT=$(smartctl -d sat -H -A -l selftest "$d" 2>/dev/null)
    H=$(echo "$OUT" | awk -F': ' '/overall-health/{print $2}')
    R=$(echo "$OUT" | awk '$1==5{print $10}')
    P=$(echo "$OUT" | awk '$1==197{print $10}')
    T=$(echo "$OUT" | awk '$1==194{print $10}')
    ST=$(echo "$OUT" | awk '/^# 1 /{sub(/^# 1 +/,""); print; exit}')
    line="  smart $a: ${H:-?} realloc=${R:-?} pending=${P:-?} temp=${T:-?}C"
    if [ "$H" != "PASSED" ] || [ "${R:-1}" != "0" ] || [ "${P:-1}" != "0" ]; then
        TLDR+="⚠️${line}\n"; fail "$a SMART realloc/pending"
    else
        TLDR+="${line} ✓\n"
    fi
    BODY+="$a: last self-test: ${ST:-none yet}\n"
done
BODY+="\n"

# --- 02s: no SMART, so kernel errors + monthly read scan ---
KERR=$(journalctl -k --since "24 hours ago" --no-pager -q 2>/dev/null | grep -ciE \
    'I/O error|blk_update_request|Buffer I/O|critical medium error|EXT4-fs error|uas_eh_' || true)
if [ "${KERR:-0}" -gt 0 ]; then
    TLDR+="⚠️  kernel disk I/O errors (24h): $KERR\n"; fail "kernel I/O errors"
else
    TLDR+="  kernel disk I/O errors (24h): 0 ✓\n"
fi
if [ -f "$READSCAN_LOG" ]; then
    LAST=$(grep ' end ' "$READSCAN_LOG" | tail -1)
    case "$LAST" in
        *"OK: 0 bad blocks"*) TLDR+="  02s read scan: ${LAST#* end   } ✓\n" ;;
        "")                   TLDR+="  02s read scan: running/none finished yet\n" ;;
        *)                    TLDR+="⚠️  02s read scan: ${LAST#* end   }\n"; fail "02s read scan bad" ;;
    esac
else
    TLDR+="  02s read scan: none yet (15th of the month)\n"
fi

# --- Power cut recovery events (24h) ---
if [ -f "$REMOUNT_LOG" ]; then
    SINCE=$(date -d '24 hours ago' '+%F %T')
    RM=$(awk -v s="$SINCE" '/^[0-9]{4}-/ && ($1" "$2) >= s' "$REMOUNT_LOG" | grep -c . || true)
    [ "${RM:-0}" -gt 0 ] && TLDR+="  auto-remounts (24h): $RM (see $REMOUNT_LOG)\n"
    BODY+="=== REMOUNT LOG (last 8) ===\n$(tail -8 "$REMOUNT_LOG")\n\n"
fi

# --- Power ---
AC=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)
BAT=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)
if [ "$AC" = "0" ]; then
    TLDR+="⚠️  power: ON BATTERY (${BAT}%)\n"; fail "on battery"
else
    TLDR+="  power: AC, battery ${BAT}% ✓\n"
fi

# --- Fleet heartbeat + metrics server ---
if [ -f "$HEARTBEAT" ]; then
    HA=$(( NOW - $(stat -c %Y "$HEARTBEAT") ))
    if [ "$HA" -gt 600 ]; then TLDR+="⚠️  fleet heartbeat: stale ($(fmt_age $HA))\n"; fail "heartbeat stale"
    else TLDR+="  fleet heartbeat: $(fmt_age $HA) old ✓\n"; fi
else
    TLDR+="⚠️  fleet heartbeat: missing\n"; fail "heartbeat missing"
fi
if systemctl is-active -q fleet_metrics_server; then
    TLDR+="  fleet_metrics_server: active ✓\n"
else
    TLDR+="⚠️  fleet_metrics_server: NOT running\n"; fail "metrics server down"
fi

# --- Wi-Fi (only network path) ---
SIG=$(iw dev wlp2s0 link 2>/dev/null | awk '/signal/{print $2" "$3}')
TLDR+="  wi-fi: ${SIG:-not connected?}\n"

# --- Monitor state in body ---
BODY+="=== HEALTH MONITOR STATE ===\n$(cat "$MONITOR_STATE" 2>/dev/null)\n"

if [ "$REASON" = "all healthy" ]; then EMOJI="✅"; else EMOJI="⚠️"; fi
SUBJECT="${EMOJI} 9046unix nightly $(date '+%Y-%m-%d') — ${REASON}"
{
    echo "To: $TO"
    echo "Cc: $CC"
    echo "Subject: $SUBJECT"
    echo ""
    echo "============================= TLDR ==============================="
    echo -e "$TLDR"
    echo "=================================================================="
    echo ""
    echo -e "$BODY"
} | msmtp "$TO" "$CC"
