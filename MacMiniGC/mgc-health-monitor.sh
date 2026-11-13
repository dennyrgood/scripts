#!/opt/homebrew/bin/bash
# mgc-health-monitor.sh -- MacMiniGC (mgc) service health monitor, every 5 min via launchd
# (com.dennis.mgc-health-monitor.plist).
# Created: 2026-11-13 14:05 UTC. Modelled on FleetDev/fleetdev-health-monitor.sh (missing-vs-down,
# 2-sample streaks, 30-min re-alert, all-clear, one stdout line per run) plus the Plex/Syncthing/
# disk checks from MathesMacMini/mathes-mac-mini-health-monitor.sh, since mgc is a Plex +
# Syncthing box like mmm. Drafted before Plex/Syncthing/GC_Media existed: re-test after Phase 7.
#
# Differences from mmm's version:
#   - Syncthing is Homebrew's (brew services), not Syncthing.app, so the process pattern differs.
#   - The Syncthing API key is read at run time from Syncthing's config.xml, not hardcoded:
#     this repo is public.
#   - GC_MEDIA: the 24TB drive must be mounted. Plex scanning an unmounted /Volumes path sees
#     empty libraries.
#   - SMART: overall health + temperature of the 24TB drive. macOS needs a USB SMART driver for
#     this; if smartctl can't open the drive, this script says nothing (no 5-min nagging) and the
#     nightly summary reports it instead.
#   - The Receive Only folder (immich-restic) showing local changes is flagged: nothing on mgc
#     should ever write to the off-site restic repo.
#   - No UPS/NUT, no TMDB Explorer.

HOST="MacMiniGC"                  # must match the writer's heartbeat_<HOST>.txt filename
TO="dennyrgood@yahoo.com"
MSMTP="/opt/homebrew/bin/msmtp"
SMARTCTL="/opt/homebrew/bin/smartctl"
JQ="/usr/bin/jq"
STATE_FILE="/tmp/mgc-monitor-state.tmp"
NOW=$(date +%s)
ALERT_INTERVAL=$((30 * 60))
FAIL_THRESHOLD=2                  # consecutive 5-min samples before alerting (anti-flap)

VOLUME="/Volumes/GC_Media"
DISK_THRESHOLD=85                 # percent used
DISK_PATHS=("/System/Volumes/Data" "$VOLUME")   # internal SSD (user data) + the 24TB
SMART_TEMP_MAX=55                 # deg C; Seagate rates its desktop HDDs to 60 C operating

PLEX_PROC_PATTERN="Plex Media Server.app/Contents/MacOS/Plex Media Server"
PLEX_URL="http://127.0.0.1:32400/identity"
SYNCTHING_PROC_PATTERN="opt/syncthing/bin/syncthing"
SYNCTHING_BASE="http://127.0.0.1:8384"
SYNCTHING_URL="$SYNCTHING_BASE/rest/noauth/health"
SYNCTHING_CONFIG_XML="$HOME/Library/Application Support/Syncthing/config.xml"
SYNCTHING_PULL_ERR_THRESHOLD=5    # same threshold as mmm / Status/checkers/syncthing_checker.py
HEARTBEAT_WRITER_PROC_PATTERN="onedrive_heartbeat_writer_all_macs.py"
HEARTBEAT_FILE="$HOME/fleet_monitor/heartbeat_${HOST}.txt"
HEARTBEAT_STALE_SECS=600          # writer ticks every 150s; 4x margin
METRICS_SERVER_PROC_PATTERN="fleet_metrics_server.py"
METRICS_SERVER_URL="http://127.0.0.1:9100/heartbeat_${HOST}.txt"

# GC_MEDIA, DISK and SMART have no process: they can only be "down" (a problem), never "missing".
SERVICES="GC_MEDIA DISK SMART PLEX SYNCTHING HEARTBEAT_WRITER METRICS_SERVER"

# --- Load state (defaults to zero/inactive if file absent) ---
for svc in $SERVICES; do
    eval "MISSING_${svc}_LAST_ALERT=0; MISSING_${svc}_ACTIVE=0; MISSING_${svc}_STREAK=0"
    eval "DOWN_${svc}_LAST_ALERT=0;    DOWN_${svc}_ACTIVE=0;    DOWN_${svc}_STREAK=0"
done
[ -f "$STATE_FILE" ] && source "$STATE_FILE"

declare -A MISSING_TRIGGERED DOWN_TRIGGERED DETAIL
for svc in $SERVICES; do MISSING_TRIGGERED[$svc]=0; DOWN_TRIGGERED[$svc]=0; DETAIL[$svc]=""; done

down() { DOWN_TRIGGERED[$1]=1; DETAIL[$1]+="$2\n"; }

# Process presence, then HTTP 200 if a URL is given (same as FleetDev/mmm).
check_service() {
    local svc=$1 pattern=$2 url=$3 code
    if ! pgrep -f "$pattern" >/dev/null 2>&1; then
        MISSING_TRIGGERED[$svc]=1
        return
    fi
    [ -z "$url" ] && return
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    [ "$code" = "200" ] || down "$svc" "Process is running but $url returned ${code:-no reply} (want 200)."
}

# --- GC_Media mounted ---
VOLUME_MOUNTED=1
if ! mount | grep -qF " on ${VOLUME} ("; then
    VOLUME_MOUNTED=0
    down GC_MEDIA "${VOLUME} is not mounted. The Plex libraries and all six Syncthing folders live on it."
fi

# --- Disk usage ---
for p in "${DISK_PATHS[@]}"; do
    [ "$p" = "$VOLUME" ] && [ "$VOLUME_MOUNTED" -eq 0 ] && continue
    pct=$(df -P "$p" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}')
    [ -n "$pct" ] && [ "$pct" -ge "$DISK_THRESHOLD" ] && down DISK "${p} is ${pct}% full (threshold ${DISK_THRESHOLD}%)."
done

# --- SMART health + temperature of the 24TB drive ---
# The disk number can change between boots, so find it from the mounted volume:
# GC_Media (APFS) -> its physical store diskNs2 -> whole disk diskN.
# -n standby,0: don't spin up a sleeping drive just to read SMART (exit 0, no data).
# smartctl exit bit 1 (value 2) = couldn't open the device (no USB SMART driver): stay quiet.
SMART_DEV=""
if [ "$VOLUME_MOUNTED" -eq 1 ]; then
    SMART_DEV=$(diskutil info "$VOLUME" 2>/dev/null | awk -F': *' '/APFS Physical Store/ {print $2}' | sed -E 's/s[0-9]+$//')
fi
if [ -n "$SMART_DEV" ] && [ -x "$SMARTCTL" ]; then
    SM_JSON=$("$SMARTCTL" -j -H -A -n standby,0 "/dev/$SMART_DEV" 2>/dev/null)
    SM_RC=$?
    if [ $((SM_RC & 2)) -eq 0 ] && [ -n "$SM_JSON" ]; then
        passed=$(echo "$SM_JSON" | "$JQ" -r '.smart_status.passed // empty' 2>/dev/null)
        temp=$(echo "$SM_JSON" | "$JQ" -r '.temperature.current // empty' 2>/dev/null)
        [ "$passed" = "false" ] && down SMART "SMART overall health on /dev/${SMART_DEV}: FAILED."
        [ $((SM_RC & 16)) -ne 0 ] && down SMART "A pre-failure SMART attribute on /dev/${SMART_DEV} is at or past its threshold."
        [ -n "$temp" ] && [ "$temp" -gt "$SMART_TEMP_MAX" ] 2>/dev/null \
            && down SMART "Drive temperature ${temp} C (threshold ${SMART_TEMP_MAX} C)."
    fi
fi

# --- Services ---
check_service PLEX "$PLEX_PROC_PATTERN" "$PLEX_URL"
check_service SYNCTHING "$SYNCTHING_PROC_PATTERN" "$SYNCTHING_URL"
check_service HEARTBEAT_WRITER "$HEARTBEAT_WRITER_PROC_PATTERN" ""
check_service METRICS_SERVER "$METRICS_SERVER_PROC_PATTERN" "$METRICS_SERVER_URL"

# --- Syncthing per-folder state (a folder in "error" still answers /rest/noauth/health 200) ---
if [ "${MISSING_TRIGGERED[SYNCTHING]}" -eq 0 ] && [ "${DOWN_TRIGGERED[SYNCTHING]}" -eq 0 ]; then
    ST_KEY=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$SYNCTHING_CONFIG_XML" 2>/dev/null | head -1)
    ST_CONFIG=""
    [ -n "$ST_KEY" ] && ST_CONFIG=$(curl -s -H "X-API-Key: $ST_KEY" --max-time 5 "$SYNCTHING_BASE/rest/config" 2>/dev/null)
    if [ -z "$ST_CONFIG" ]; then
        down SYNCTHING "Could not read folder state from $SYNCTHING_BASE/rest/config (API key from $SYNCTHING_CONFIG_XML)."
    else
        ST_PULL_ERRS=0
        while IFS=$'\t' read -r fid label ftype; do
            [ -z "$fid" ] && continue
            DB=$(curl -s -H "X-API-Key: $ST_KEY" --max-time 5 \
                 --get --data-urlencode "folder=$fid" "$SYNCTHING_BASE/rest/db/status" 2>/dev/null)
            STATE=$(echo "$DB" | "$JQ" -r '.state // "unknown"' 2>/dev/null)
            PE=$(echo "$DB" | "$JQ" -r '.pullErrors // 0' 2>/dev/null)
            RO=$(echo "$DB" | "$JQ" -r '.receiveOnlyTotalItems // 0' 2>/dev/null)
            if [ "$STATE" = "error" ]; then
                down SYNCTHING "Folder '${label:-$fid}' is in error state."
            elif [ "${PE:-0}" -gt 0 ] 2>/dev/null; then
                ST_PULL_ERRS=$((ST_PULL_ERRS + PE))
            fi
            if [ "$ftype" = "receiveonly" ] && [ "${RO:-0}" -gt 0 ] 2>/dev/null; then
                down SYNCTHING "Receive Only folder '${label:-$fid}' has ${RO} locally changed item(s). Nothing on mgc should write there."
            fi
        done < <(echo "$ST_CONFIG" | "$JQ" -r '.folders[] | [.id, .label, .type] | @tsv' 2>/dev/null)
        [ "$ST_PULL_ERRS" -gt "$SYNCTHING_PULL_ERR_THRESHOLD" ] \
            && down SYNCTHING "${ST_PULL_ERRS} failed items across folders (threshold ${SYNCTHING_PULL_ERR_THRESHOLD})."
    fi
fi

# --- Heartbeat-writer freshness (no HTTP endpoint, so a hang only shows as a stale file) ---
if [ "${MISSING_TRIGGERED[HEARTBEAT_WRITER]}" -eq 0 ]; then
    if [ ! -f "$HEARTBEAT_FILE" ]; then
        down HEARTBEAT_WRITER "${HEARTBEAT_FILE} does not exist."
    else
        HB_AGE=$(( NOW - $(stat -f %m "$HEARTBEAT_FILE") ))
        [ "$HB_AGE" -gt "$HEARTBEAT_STALE_SECS" ] \
            && down HEARTBEAT_WRITER "${HEARTBEAT_FILE} last written $((HB_AGE / 60))m ago (threshold $((HEARTBEAT_STALE_SECS / 60))m)."
    fi
fi

# --- Evaluate each condition: alert / suppress / clear / ok (unchanged from FleetDev) ---
check_condition_streak() {
    local triggered=$1 last_alert=$2 was_active=$3 streak=$4
    if [ "$triggered" -eq 1 ]; then
        streak=$(( streak + 1 ))
        if [ "$streak" -ge "$FAIL_THRESHOLD" ]; then
            if [ "$was_active" -eq 0 ] || [ $(( NOW - last_alert )) -ge $ALERT_INTERVAL ]; then
                echo "alert $streak"
            else
                echo "suppress $streak"
            fi
        else
            echo "wait $streak"
        fi
    elif [ "$was_active" -eq 1 ]; then
        echo "clear 0"
    else
        echo "ok 0"
    fi
}

ALERT_BODY=""
CLEAR_BODY=""
for svc in $SERVICES; do
    trig=${MISSING_TRIGGERED[$svc]}
    last=$(eval echo \$MISSING_${svc}_LAST_ALERT)
    active=$(eval echo \$MISSING_${svc}_ACTIVE)
    streak=$(eval echo \$MISSING_${svc}_STREAK)
    read verdict new_streak <<< "$(check_condition_streak $trig $last $active $streak)"
    eval "MISSING_${svc}_STREAK=$new_streak"
    case "$verdict" in
        alert)    eval "MISSING_${svc}_LAST_ALERT=$NOW; MISSING_${svc}_ACTIVE=1"
                  ALERT_BODY+="=== ${svc} MISSING ===\n"
                  ALERT_BODY+="No matching process for ${new_streak} consecutive checks (~$((new_streak * 5)) min).\n\n" ;;
        clear)    eval "MISSING_${svc}_ACTIVE=0"
                  CLEAR_BODY+="  - ${svc} process is back\n" ;;
        suppress) eval "MISSING_${svc}_ACTIVE=1" ;;
        wait|ok)  eval "MISSING_${svc}_ACTIVE=0" ;;
    esac

    # Skip "down" while missing, so a crash doesn't read as "responding again" (FleetDev 2026-09-04 fix).
    [ "${MISSING_TRIGGERED[$svc]}" -eq 1 ] && continue
    trig=${DOWN_TRIGGERED[$svc]}
    last=$(eval echo \$DOWN_${svc}_LAST_ALERT)
    active=$(eval echo \$DOWN_${svc}_ACTIVE)
    streak=$(eval echo \$DOWN_${svc}_STREAK)
    read verdict new_streak <<< "$(check_condition_streak $trig $last $active $streak)"
    eval "DOWN_${svc}_STREAK=$new_streak"
    case "$verdict" in
        alert)    eval "DOWN_${svc}_LAST_ALERT=$NOW; DOWN_${svc}_ACTIVE=1"
                  ALERT_BODY+="=== ${svc} PROBLEM ===\n"
                  ALERT_BODY+="Present for ${new_streak} consecutive checks (~$((new_streak * 5)) min):\n${DETAIL[$svc]}\n" ;;
        clear)    eval "DOWN_${svc}_ACTIVE=0"
                  CLEAR_BODY+="  - ${svc} is OK again\n" ;;
        suppress) eval "DOWN_${svc}_ACTIVE=1" ;;
        wait|ok)  eval "DOWN_${svc}_ACTIVE=0" ;;
    esac
done

FOOTER="------------------------------------------------------------------------
WHAT THESE ALERTS MEAN AND WHAT TO DO
------------------------------------------------------------------------
GC_MEDIA PROBLEM: ${VOLUME} isn't mounted. Check the drive's power and USB cable,
  then: diskutil list external; diskutil mount GC_Media. Don't let Plex scan until
  it's back (empty-trash-after-scan is off, so libraries survive).

DISK PROBLEM: a volume is over ${DISK_THRESHOLD}%. du -sh ${VOLUME}/* | sort -h

SMART PROBLEM: the 24TB is failing SMART, has a pre-fail attribute at threshold,
  or is over ${SMART_TEMP_MAX} C. smartctl -a /dev/<disk> for detail. Media is
  copied from mmm and immich-restic from wbu, so nothing exists only here, but
  plan a replacement.

PLEX / SYNCTHING MISSING: the app isn't running. Plex: open -a 'Plex Media Server'.
  Syncthing: brew services restart syncthing.
PLEX / SYNCTHING PROBLEM: running but not answering, or (Syncthing) a folder is in
  error, has too many failed items, or immich-restic has local changes. Look in the
  GUI (ssh -L 8384:127.0.0.1:8384 mgc).

HEARTBEAT_WRITER / METRICS_SERVER: the fleet dashboard can't see mgc.
  launchctl kickstart -k gui/\$(id -u)/com.dennis.heartbeat-writer   (or .fleet-metrics-server)
  logs: ~/Library/Logs/heartbeat_writer.log, fleet_metrics_server.log
------------------------------------------------------------------------"

# --- Save state ---
{
    for svc in $SERVICES; do
        for k in MISSING_${svc}_LAST_ALERT MISSING_${svc}_ACTIVE MISSING_${svc}_STREAK \
                 DOWN_${svc}_LAST_ALERT DOWN_${svc}_ACTIVE DOWN_${svc}_STREAK; do
            echo "$k=$(eval echo \$$k)"
        done
    done
} > "$STATE_FILE"

if [ -n "$ALERT_BODY" ]; then
    {
        echo "Subject: [${HOST}] HEALTH ALERT -- $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo -e "$ALERT_BODY"
        echo "$FOOTER"
    } | "$MSMTP" -a icloud "$TO"
fi
if [ -n "$CLEAR_BODY" ]; then
    {
        echo "Subject: [${HOST}] ALL CLEAR -- $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo "The following conditions have resolved:"
        echo ""
        echo -e "$CLEAR_BODY"
    } | "$MSMTP" -a icloud "$TO"
fi

# One line per run, always, so the launchd log proves the job ran.
ACTIVE_COUNT=$(grep -c "_ACTIVE=1" "$STATE_FILE" 2>/dev/null || true)
echo "$(date '+%Y-%m-%d %H:%M:%S') check complete -- ${ACTIVE_COUNT:-0} active alert(s)"
