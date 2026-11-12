#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-nightly-summary.sh
# 2026-11-08 — created, same shape as ChatWorkhorseUnix/cwhu-nightly-summary.sh.
# 2026-11-09 04:05 UTC — "files in 24h" also reads <log>.1, since the pull logs are now
# rotated by size (/etc/logrotate.d/9046unix-pull-logs, delaycompress keeps .1 plain).
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
HEARTBEAT="/home/dhm/fleet_monitor/heartbeat_9046unix.txt"
ARCHIVES=(archive00p archive01p)
MARKER=".archive-mounted"
# by-id paths: sdX letters shuffle between boots.
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

# --- Backups pulled from FleetNAS (9046unix-nightly-pull.sh: @reboot + 03:00) ---
# Per folder: bytes on the archive vs. the source on FleetNAS (ssh as dhm; rsync's
# /<dir>/ is /volume1/<dir> in an ssh shell). Source size is cached (frozen
# photo_legacy: weekly; others: daily) because du over ~838 GB on the NAS is slow.
# One row per night in /var/lib/9046unix/progress-<key>.tsv gives growth and an ETA.
# "Copying" is OK during a seed; after a first complete run, the warning is: no
# complete run in 3 days. photo_legacy waits (no warning) until Immich has finished.
STATE_DIR=/var/lib/9046unix
mkdir -p "$STATE_DIR"
[ -f "$STATE_DIR/immich-progress.tsv" ] && mv "$STATE_DIR/immich-progress.tsv" "$STATE_DIR/progress-immich.tsv"
GB() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1e9}'; }
pull_report() {   # <nas-dir> <archive-mount> <short label> <per-file log> <src-size max age, s>
    local dir=$1 mnt=$2 label=$3 flog=$4 maxage=$5
    local key=${dir//\//_}
    local ok="/home/dhm/.seed-pull-$key.ok" tsv="$STATE_DIR/progress-$key.tsv" cache="$STATE_DIR/src-size-$key"
    local dst_b src_b prev_b prev_t size pct delta="" eta="" d hrs newfiles line pa busy
    # images/backups is not copied (nightly-pull excludes it), so leave it out of both sides
    dst_b=$(du -sb --exclude=.versions --exclude='*/immich/images/backups' "$mnt/$dir" 2>/dev/null | awk '{print $1}')
    if [ ! -s "$cache" ] || [ $(( NOW - $(stat -c %Y "$cache") )) -gt "$maxage" ]; then
        src_b=$(timeout 900 sudo -u dhm ssh -o BatchMode=yes -o ConnectTimeout=20 dhm@192.168.178.123 \
                "du -sb --exclude='#recycle' --exclude='*/immich/images/backups' /volume1/$dir" 2>/dev/null | awk '{print $1}')
        [ -n "$src_b" ] && echo "$src_b" > "$cache"
    fi
    src_b=$(cat "$cache" 2>/dev/null)
    prev_t=$(tail -1 "$tsv" 2>/dev/null | awk '{print $1}')
    prev_b=$(tail -1 "$tsv" 2>/dev/null | awk '{print $2}')
    [ -n "$dst_b" ] && printf '%s\t%s\t%s\n' "$NOW" "$dst_b" "${src_b:-}" >> "$tsv"

    size="$(GB "${dst_b:-0}") GB"
    if [ -n "$src_b" ] && [ "$src_b" -gt 0 ]; then
        pct=$(awk -v d="${dst_b:-0}" -v s="$src_b" 'BEGIN{p=100*d/s; if(p>100)p=100; printf "%d", p}')
        size="$(GB "${dst_b:-0}") of $(GB "$src_b") GB (${pct}%)"
    fi
    if [ -n "$prev_b" ] && [ -n "$dst_b" ] && [ -n "$prev_t" ] && [ $(( NOW - prev_t )) -gt 3600 ]; then
        d=$(( dst_b - prev_b )); hrs=$(( (NOW - prev_t) / 3600 ))
        delta=", +$(GB $d) GB in ${hrs}h"
        if [ -n "$src_b" ] && [ "$d" -gt 0 ] && [ "$src_b" -gt "$dst_b" ]; then
            eta=$(awk -v r="$(( src_b - dst_b ))" -v d="$d" -v h="$hrs" 'BEGIN{printf ", ~%.1f days to go", (r/d)*h/24}')
        fi
    fi
    newfiles=$(awk -v s="$(date -d '24 hours ago' '+%Y/%m/%d %H:%M:%S')" \
        '($1" "$2) >= s && $4 ~ /^>f/' "$flog.1" "$flog" 2>/dev/null | wc -l)

    if pgrep -f "^rsync .*192\.168\.178\.123:/${dir}/" >/dev/null; then
        TLDR+="  ${label}: copying, ${size}${delta}${eta} ✓\n"
    elif [ -f "$ok" ]; then
        pa=$(( NOW - $(cat "$ok") ))
        line="${label}: ${size}, last complete run $(fmt_age $pa) ago, ${newfiles} files copied in 24h"
        # pulls run one at a time, so a job waiting behind another one's rsync is queued, not stale
        busy=$(pgrep -a rsync | grep -o '192\.168\.178\.123:/[^/ ]*' | head -1 | sed 's/.*://; s/^\///')
        if [ -n "$busy" ] && [ "$pa" -le 604800 ]; then
            TLDR+="  ${label}: queued behind ${busy}, ${size}, last complete run $(fmt_age $pa) ago ✓\n"
        elif [ "$pa" -gt 259200 ]; then TLDR+="⚠️  ${line}\n"; fail "$dir backup stale"
        else TLDR+="  ${line} ✓\n"; fi
    elif [ "$dir" = "photo_legacy" ] && [ ! -f /home/dhm/.seed-pull-immich.ok ]; then
        TLDR+="  ${label}: waiting for Immich to finish first (${size})\n"
    elif [ "$dir" = "photo_legacy" ] && [ -n "$dst_b" ] && [ "${prev_b:-0}" -lt "$dst_b" ]; then
        TLDR+="  ${label}: paused for the night, ${size}${delta}${eta} ✓\n"
    elif [ -n "$NAS_DOWN" ]; then
        TLDR+="⚠️  ${label}: waiting for FleetNAS (${size})\n"
    else
        TLDR+="⚠️  ${label}: not running and never completed (${size})\n"; fail "$dir backup not running"
    fi
}
# FleetNAS outage (seed-pull.sh keeps ~/.nas-unreachable-since while port 22 is down)
NAS_DOWN=""
if [ -f /home/dhm/.nas-unreachable-since ]; then
    nd=$(cat /home/dhm/.nas-unreachable-since)
    NAS_DOWN="FleetNAS unreachable since $(date -d "@$nd" '+%a %H:%M') ($(fmt_age $(( NOW - nd ))))"
    TLDR+="⚠️  ${NAS_DOWN} — copies retry until 02:50\n"; fail "FleetNAS unreachable"
fi
pull_report immich       /mnt/archive01p "immich -> 01p"       /home/dhm/sync-initial.log  86400
pull_report misc/money   /mnt/archive00p "money -> 00p"        /home/dhm/rsync-misc_money.log 86400
pull_report photo_legacy /mnt/archive00p "photo_legacy -> 00p" /home/dhm/rsync-photo_legacy.log 604800
NV=$(find /mnt/archive00p/misc/.versions -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
[ "$NV" -gt 0 ] && TLDR+="  money versions kept: $NV day(s) in /mnt/archive00p/misc/.versions\n"
BODY+="=== NAS PULLS (last 6 results, ~/nightly-pull.log) ===\n$(grep -E 'DONE|PAUSED|error|stopping|skipping|gave up|no .*marker|waiting|unreachable' /home/dhm/nightly-pull.log /home/dhm/immich-pull.log 2>/dev/null | tail -6 | sed 's#^/home/dhm/##')\n\n"

# --- Household latency, last 24 h (9046unix-latency-log.sh, every 5 min) ---
# Is the NAS copy adding lag for the gamer / evening Netflix? Compares samples taken
# with the copy running vs. with no copy traffic (paused for the sample, or idle),
# split into late afternoon (15-18 local, gaming), evening (18-24, gaming + Netflix)
# and the rest of the day. Informational only:
# never changes the subject line.
LAT=/var/lib/9046unix/latency.tsv
if [ -s "$LAT" ]; then
    LAT_TXT=$(awk -F'\t' -v since=$(( NOW - 86400 )) '
        $1 >= since && $6 != "NA" {
            h = $2 + 0
            band  = (h >= 18) ? "evening 18-24" : (h >= 15) ? "afternoon 15-18" : "rest of day  "
            state = ($3 == "copy") ? "copy" : "nocopy"
            k = band SUBSEP state
            n[k]++; ravg[k] += $4; iavg[k] += $6
            if ($7 > 100) spike[k]++
            if ($7 > imax[k]) imax[k] = $7
        }
        function one(k) {
            if (!n[k]) return "no samples"
            return sprintf("%3.0f ms avg (router %2.0f), worst %3.0f, spikes %d/%d", iavg[k]/n[k], ravg[k]/n[k], imax[k], spike[k], n[k])
        }
        function line(b,   c, p) {
            c = b SUBSEP "copy"; p = b SUBSEP "nocopy"
            if (!n[c] && !n[p]) return
            printf "    %s\n      copy on: %s\n      no copy: %s\n", b, one(c), one(p)
        }
        END { line("afternoon 15-18"); line("evening 18-24"); line("rest of day  ") }' "$LAT")
    TLDR+="  latency 24h (explained in the body):\n"
    BODY+="=== HOUSEHOLD LATENCY, last 24h (ping router + 1.1.1.1 every 5 min) ===\n"
    BODY+="Each line: average internet ping (1.1.1.1), average router ping, worst single ping,\n"
    BODY+="and spikes = samples whose worst ping was >100 ms, out of all samples.\n"
    BODY+="'no copy' samples pause the copy for ~15 s (every other sample), so both are measured\n"
    BODY+="at the same times of day. If 'copy on' is clearly worse from 15-24, lower the\n"
    BODY+="limit or skip those hours; if they look alike, the copy isn't the cause of any lag.\n"
    TLDR+="${LAT_TXT}\n"
fi

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

# --- kernel disk errors (02s read scan removed 2026-11-12 with 02s) ---
KERR=$(journalctl -k --since "24 hours ago" --no-pager -q 2>/dev/null | grep -ciE \
    'I/O error|blk_update_request|Buffer I/O|critical medium error|EXT4-fs error|uas_eh_' || true)
if [ "${KERR:-0}" -gt 0 ]; then
    TLDR+="⚠️  kernel disk I/O errors (24h): $KERR\n"; fail "kernel I/O errors"
else
    TLDR+="  kernel disk I/O errors (24h): 0 ✓\n"
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
# Buffer the message so a send that dies on a Wi-Fi blip can be retried.
MSG=$({
    echo "To: $TO"
    echo "Cc: $CC"
    echo "Subject: $SUBJECT"
    echo ""
    echo "============================= TLDR ==============================="
    echo -e "$TLDR"
    echo "=================================================================="
    echo ""
    echo -e "$BODY"
})
for attempt in 1 2 3; do
    printf '%s\n' "$MSG" | timeout 120 msmtp "$TO" "$CC" && break
    echo "$(date) msmtp attempt $attempt failed (rc=$?)"
    [ "$attempt" -lt 3 ] && sleep 300
done
