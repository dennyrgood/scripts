#!/bin/bash
# mgc-nightly-summary.sh -- daily health summary email for MacMiniGC (mgc), 07:00 via launchd
# (com.dennis.mgc-nightly-summary.plist).
# Created: 2026-11-13 14:05 UTC. Modelled on FleetDev/fleetdev-nightly-summary.sh (TLDR first,
# health-monitor freshness + per-service status, full state dump last, Cc to iCloud for
# Status/fleet_digest.py, 7 send tries 10 min apart). mgc-specific sections: GC_Media mount + usage,
# SMART/temperature readout of the 24TB, Syncthing per-folder completion, Plex up/version, and the
# monthly off-site restic verify result. Drafted before Plex/Syncthing/GC_Media existed: re-test
# after Phase 7.
#
# Sends via msmtp (iCloud SMTP, ~/.msmtprc account "icloud"). launchd gives a minimal PATH, so
# every Homebrew tool is called by full path.
#
# 2026-11-13 15:10 UTC: fixed "last boot" (the sed captured usec, so it showed 1970-01-09); service
# column widened to 18 (HEARTBEAT_WRITER: overflowed 17); SMART "unreadable" is now an info line,
# not a failure: no USB SMART driver on mgc (headless, so the kext's Reduced Security can't be set;
# Dennis 2026-11-13), and it would otherwise turn every nightly ⚠️.

MSMTP="/opt/homebrew/bin/msmtp"
SMARTCTL="/opt/homebrew/bin/smartctl"
JQ="/usr/bin/jq"
TO="dennyrgood@yahoo.com"
HOST="MacMiniGC"                  # also the fleet_digest.py display name (add it to EXPECTED_HOSTS)
MONITOR_STATE="/tmp/mgc-monitor-state.tmp"
MONITOR_LOG="$HOME/Library/Logs/mgc_health_monitor.log"
MONITOR_STALE_SECS=1800           # 6x the 5-min run interval
VOLUME="/Volumes/GC_Media"
SYNCTHING_BASE="http://127.0.0.1:8384"
SYNCTHING_CONFIG_XML="$HOME/Library/Application Support/Syncthing/config.xml"
PLEX_URL="http://127.0.0.1:32400/identity"
RESTIC_JSON="$HOME/fleet_monitor/watchdog_restic-offsite_macminigc.json"
RESTIC_STALE_SECS=$((35 * 86400)) # monthly job (day 15), a few days' grace
SEND_TRIES=7
SEND_WAIT_SECS=600

OK=1
REASON="all healthy"
fail() { [ "$OK" -eq 1 ] && { OK=0; REASON="$1"; }; }

fmt_age() {
    local secs=$1
    if   [ "$secs" -lt 3600 ];   then echo "$((secs / 60))m"
    elif [ "$secs" -lt 172800 ]; then echo "$((secs / 3600))h"
    else echo "$((secs / 86400))d"
    fi
}

svc_status() {
    local svc=$1 missing down
    missing=$(grep "^MISSING_${svc}_ACTIVE=" "$MONITOR_STATE" 2>/dev/null | cut -d= -f2)
    down=$(grep "^DOWN_${svc}_ACTIVE=" "$MONITOR_STATE" 2>/dev/null | cut -d= -f2)
    if   [ "$missing" = "1" ]; then echo "⚠️ MISSING"
    elif [ "$down" = "1" ];    then echo "⚠️ PROBLEM"
    else echo "✓"
    fi
}

TLDR="============================= TLDR ===============================\n"
BODY=""

# --- Uptime (a recent boot after a power cut is worth seeing) ---
BOOT_TS=$(sysctl -n kern.boottime 2>/dev/null | sed -E 's/^\{ sec = ([0-9]+),.*/\1/')
[ -n "$BOOT_TS" ] && TLDR+="  last boot: $(date -r "$BOOT_TS" '+%Y-%m-%d %H:%M') ($(fmt_age $(( $(date +%s) - BOOT_TS ))) ago)\n"

# --- GC_Media mount + usage ---
if mount | grep -qF " on ${VOLUME} ("; then
    USAGE=$(df -H "$VOLUME" | awk 'NR==2 {print $5" used, "$4" free of "$2}')
    TLDR+="  GC_Media: mounted, ${USAGE} ✓\n"
    MOUNTED=1
else
    TLDR+="  GC_Media: ⚠️ NOT MOUNTED\n"
    fail "GC_Media not mounted"
    MOUNTED=0
fi
TLDR+="  internal SSD: $(df -H /System/Volumes/Data | awk 'NR==2 {print $5" used, "$4" free"}')\n"

# --- SMART / temperature of the 24TB ---
SMART_DEV=""
[ "$MOUNTED" -eq 1 ] && SMART_DEV=$(diskutil info "$VOLUME" 2>/dev/null | awk -F': *' '/APFS Physical Store/ {print $2}' | sed -E 's/s[0-9]+$//')
if [ -z "$SMART_DEV" ]; then
    TLDR+="  SMART: ⚠️ skipped (GC_Media not mounted, can't find its disk)\n"
else
    SM_JSON=$("$SMARTCTL" -j -a "/dev/$SMART_DEV" 2>/dev/null)
    SM_RC=$?
    if [ $((SM_RC & 2)) -ne 0 ] || [ -z "$SM_JSON" ]; then
        TLDR+="  SMART: n/a (/dev/${SMART_DEV} not readable over USB without a SMART driver; none installed, by decision)\n"
    else
        attr() { echo "$SM_JSON" | "$JQ" -r ".ata_smart_attributes.table[]? | select(.id==$1) | .raw.value" 2>/dev/null; }
        PASSED=$(echo "$SM_JSON" | "$JQ" -r '.smart_status.passed // "unknown"')
        TEMP=$(echo "$SM_JSON" | "$JQ" -r '.temperature.current // "?"')
        HOURS=$(echo "$SM_JSON" | "$JQ" -r '.power_on_time.hours // "?"')
        LINE="health $([ "$PASSED" = "true" ] && echo PASSED || echo "$PASSED"), ${TEMP} C, ${HOURS} h on"
        LINE+=", realloc $(attr 5), pending $(attr 197), offline-unc $(attr 198), CRC $(attr 199)"
        if [ "$PASSED" = "true" ] && [ $((SM_RC & 0xF8)) -eq 0 ]; then
            TLDR+="  SMART /dev/${SMART_DEV}: ${LINE} ✓\n"
        else
            TLDR+="  SMART /dev/${SMART_DEV}: ⚠️ ${LINE} (smartctl exit ${SM_RC})\n"
            fail "SMART warning on the 24TB"
        fi
    fi
fi

# --- Health monitor freshness + per-service status ---
if [ -f "$MONITOR_STATE" ]; then
    MONITOR_AGE=$(( $(date +%s) - $(stat -f %m "$MONITOR_STATE") ))
    if [ "$MONITOR_AGE" -gt "$MONITOR_STALE_SECS" ]; then
        TLDR+="  mgc-health-monitor: ⚠️ stale (last run $((MONITOR_AGE / 60))m ago)\n"
        fail "health monitor stale"
    else
        TLDR+="  mgc-health-monitor: last run $((MONITOR_AGE / 60))m ago ✓\n"
    fi
    MONITOR_ACTIVE=$(grep "_ACTIVE=1" "$MONITOR_STATE" 2>/dev/null)
    if [ -n "$MONITOR_ACTIVE" ]; then
        TLDR+="  mgc-health-monitor: ⚠️ active alerts\n"
        fail "active health alerts"
    else
        TLDR+="  mgc-health-monitor: no active alerts ✓\n"
    fi
    for s in GC_MEDIA DISK SMART PLEX SYNCTHING HEARTBEAT_WRITER METRICS_SERVER; do
        TLDR+="    $(printf '%-18s' "$s:") $(svc_status $s)\n"
    done
else
    TLDR+="  mgc-health-monitor: ⚠️ state file missing ($MONITOR_STATE)\n"
    fail "health monitor never ran"
fi

# --- Plex ---
PLEX_ID=$(curl -s --max-time 5 "$PLEX_URL" 2>/dev/null)
if [ -n "$PLEX_ID" ]; then
    TLDR+="  Plex: up, $(echo "$PLEX_ID" | grep -oE 'version="[^"]*"' | head -1) ✓\n"
else
    TLDR+="  Plex: ⚠️ no answer on $PLEX_URL\n"
    fail "Plex not answering"
fi

# --- Syncthing per-folder completion ---
ST_KEY=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$SYNCTHING_CONFIG_XML" 2>/dev/null | head -1)
ST_CONFIG=""
[ -n "$ST_KEY" ] && ST_CONFIG=$(curl -s -H "X-API-Key: $ST_KEY" --max-time 5 "$SYNCTHING_BASE/rest/config" 2>/dev/null)
if [ -z "$ST_CONFIG" ]; then
    TLDR+="  Syncthing: ⚠️ API not reachable\n"
    fail "Syncthing API not reachable"
else
    TLDR+="  Syncthing:\n"
    while IFS=$'\t' read -r fid label ftype; do
        [ -z "$fid" ] && continue
        DB=$(curl -s -H "X-API-Key: $ST_KEY" --max-time 5 --get --data-urlencode "folder=$fid" "$SYNCTHING_BASE/rest/db/status" 2>/dev/null)
        CP=$(curl -s -H "X-API-Key: $ST_KEY" --max-time 5 --get --data-urlencode "folder=$fid" "$SYNCTHING_BASE/rest/db/completion" 2>/dev/null)
        STATE=$(echo "$DB" | "$JQ" -r '.state // "?"')
        PE=$(echo "$DB" | "$JQ" -r '.pullErrors // 0')
        RO=$(echo "$DB" | "$JQ" -r '.receiveOnlyTotalItems // 0')
        PCT=$(echo "$CP" | "$JQ" -r '.completion // 0 | floor')
        NEED=$(echo "$CP" | "$JQ" -r '.needItems // 0')
        LINE="$(printf '%-20s' "${label:-$fid}") ${ftype}, ${STATE}, ${PCT}%"
        [ "$NEED" -gt 0 ] 2>/dev/null && LINE+=", ${NEED} items to go"
        [ "$PE" -gt 0 ] 2>/dev/null && LINE+=", ${PE} failed"
        [ "$ftype" = "receiveonly" ] && [ "$RO" -gt 0 ] 2>/dev/null && LINE+=", ${RO} LOCALLY CHANGED"
        if [ "$STATE" = "error" ] || { [ "$ftype" = "receiveonly" ] && [ "$RO" -gt 0 ] 2>/dev/null; }; then
            TLDR+="    ⚠️ ${LINE}\n"; fail "Syncthing folder ${label:-$fid}"
        else
            TLDR+="    ${LINE}\n"
        fi
    done < <(echo "$ST_CONFIG" | "$JQ" -r '.folders[] | [.id, .label, .type] | @tsv' 2>/dev/null)
fi

# --- Off-site restic verify (monthly, day 15) ---
if [ -f "$RESTIC_JSON" ]; then
    R_OK=$(  "$JQ" -r '.ok'           "$RESTIC_JSON" 2>/dev/null)
    R_NOTE=$("$JQ" -r '.note'         "$RESTIC_JSON" 2>/dev/null)
    R_FIN=$( "$JQ" -r '.finished_utc' "$RESTIC_JSON" 2>/dev/null)
    R_TS=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$R_FIN" +%s 2>/dev/null || echo 0)
    R_AGE=$(( $(date +%s) - R_TS ))
    if [ "$R_OK" != "true" ]; then
        TLDR+="  restic verify: ⚠️ ${R_NOTE} (${R_FIN})\n"; fail "restic verify failed"
    elif [ "$R_AGE" -gt "$RESTIC_STALE_SECS" ]; then
        TLDR+="  restic verify: ⚠️ last ok run $(fmt_age $R_AGE) ago\n"; fail "restic verify stale"
    else
        TLDR+="  restic verify: ${R_NOTE} ($(fmt_age $R_AGE) ago) ✓\n"
    fi
else
    TLDR+="  restic verify: ⚠️ never run ($RESTIC_JSON missing)\n"
    fail "restic verify never run"
fi

TLDR+="===================================================================\n\n"

# --- Detail: last lines of the monitor log, then the full state dump ---
BODY+="=== $MONITOR_LOG (last 5) ===\n"
BODY+="$(tail -5 "$MONITOR_LOG" 2>/dev/null || echo '(file not found)')\n\n"
BODY+="=== HEALTH MONITOR STATE ===\n"
if [ -f "$MONITOR_STATE" ]; then
    [ -n "$MONITOR_ACTIVE" ] && BODY+="ACTIVE ALERTS:\n$MONITOR_ACTIVE\n" || BODY+="No active alerts.\n"
    BODY+="\n$(cat "$MONITOR_STATE")\n"
else
    BODY+="⚠️ state file not found -- health monitor has not run\n"
fi
BODY="${TLDR}${BODY}"

[ "$OK" -eq 1 ] && EMOJI="✅" || EMOJI="⚠️"
SUBJECT="${EMOJI} ${HOST} nightly $(date '+%Y-%m-%d') — ${REASON}"

MESSAGE=$({
    echo "Subject: $SUBJECT"
    echo "Cc: dennis.mathes@icloud.com"   # fleet_digest.py reads this copy from the iCloud inbox
    echo ""
    echo -e "$BODY"
})
for TRY in $(seq 1 "$SEND_TRIES"); do
    printf '%s\n' "$MESSAGE" | "$MSMTP" -a icloud "$TO" dennis.mathes@icloud.com && exit 0
    RC=$?
    echo "$(date '+%Y-%m-%d %H:%M') send failed (try $TRY of $SEND_TRIES, msmtp exit $RC)"
    [ "$TRY" -lt "$SEND_TRIES" ] && sleep "$SEND_WAIT_SECS"
done
exit "$RC"
