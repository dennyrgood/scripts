#!/bin/bash
# Created: 2026-08-30 UTC — daily health summary email for denniss-macbook-air (mb),
# modeled on MathesMacMini/nightly_summary.sh but scoped to what actually runs on
# THIS box. No UPS/Plex/Syncthing sections — none of that runs here.
#
# 2026-09-20: dropped the comfy-fleet-scan freshness check it used to carry here.
# The scan agent (com.dennis.comfy-fleet-scan) isn't loaded on this box anymore --
# it moved to fleetdev. The plist stays in the repo (launchagents/) as a backup
# in case it's ever moved back here, but leave that plist alone; this script just
# stopped checking for a job that's intentionally not running here.
#
# Sends via msmtp (iCloud SMTP, ~/.msmtprc) — see the mmm/WBU runbooks under
# WorkBenchUnix/RUNBOOK_msmtp-credential-rotation.md for credential setup/rotation.
# Run via launchd, which gets a minimal PATH, so msmtp is called by full Homebrew
# path throughout.

MSMTP="/opt/homebrew/bin/msmtp"
TO="dennyrgood@yahoo.com"
HOST="denniss-macbook-air"
MONITOR_STATE="/tmp/denniss-macbook-air-monitor-state.tmp"
# 2026-09-04: briefly padded to 43200s (12h) after the identical bug surfaced on mb2
# (StartInterval launchd jobs don't fire/catch up during sleep, so a normal overnight
# sleep alone falsely flagged mb-health-monitor as stale). Reverted to a tight-ish
# threshold on the understanding that mb, like mb2, is always on AC power with the lid
# never closed and should also get `sudo pmset -a sleep 0 standby 0 powernap 0` run on
# it directly (that command was run on mb2 as part of this fix — confirm/run it on mb
# too if not already done). Padded a bit past the 5-min run interval to absorb ordinary
# scheduling jitter, not to ride out sleep.
MONITOR_STALE_SECS=1800   # 30 min (6x the 5-min run interval)

fmt_age() {
    local secs=$1
    if   [ "$secs" -lt 3600 ];   then echo "$((secs / 60))m"
    elif [ "$secs" -lt 172800 ]; then echo "$((secs / 3600))h"
    else echo "$((secs / 86400))d"
    fi
}

# Per-service breakdown of $MONITOR_STATE for the TLDR — reads the same
# MISSING_${svc}_ACTIVE/DOWN_${svc}_ACTIVE keys mb-health-monitor.sh already writes.
svc_status() {
    local svc=$1
    local missing down
    missing=$(grep "^MISSING_${svc}_ACTIVE=" "$MONITOR_STATE" 2>/dev/null | cut -d= -f2)
    down=$(grep "^DOWN_${svc}_ACTIVE=" "$MONITOR_STATE" 2>/dev/null | cut -d= -f2)
    if [ "$missing" = "1" ]; then
        echo "⚠️ MISSING"
    elif [ "$down" = "1" ]; then
        echo "⚠️ NOT RESPONDING"
    else
        echo "✓"
    fi
}

OK=1
REASON="all healthy"
BODY=""

# --- Health monitor watchdog (freshness + active alerts) in TLDR ---
TLDR="============================= TLDR ===============================\n"
if [ -f "$MONITOR_STATE" ]; then
    MONITOR_AGE=$(( $(date +%s) - $(stat -f %m "$MONITOR_STATE") ))
    if [ "$MONITOR_AGE" -gt "$MONITOR_STALE_SECS" ]; then
        TLDR+="  mb-health-monitor: ⚠️ stale (last-run $((MONITOR_AGE / 60))m ago; threshold $((MONITOR_STALE_SECS / 60))m)\n"
        [ "$OK" -eq 1 ] && { OK=0; REASON="health monitor stale/missing"; }
    else
        TLDR+="  mb-health-monitor: last-run $((MONITOR_AGE / 60))m ago ✓\n"
    fi
    MONITOR_ACTIVE=$(grep "_ACTIVE=1" "$MONITOR_STATE" 2>/dev/null)
    if [ -n "$MONITOR_ACTIVE" ]; then
        TLDR+="  mb-health-monitor: ⚠️ active alerts\n"
        [ "$OK" -eq 1 ] && { OK=0; REASON="active health alerts"; }
    else
        TLDR+="  mb-health-monitor: no active alerts ✓\n"
    fi
    TLDR+="    comfy-fleet-http:  $(svc_status COMFY_HTTP)\n"
    TLDR+="    metrics-server:    $(svc_status METRICS_SERVER)\n"
    TLDR+="    heartbeat-writer:  $(svc_status HEARTBEAT_WRITER)\n"
    TLDR+="    search-adv-web:    $(svc_status SEARCH_ADV)\n"
    TLDR+="    search-shows-web:  $(svc_status SEARCH_SHOWS)\n"
    TLDR+="    tmdb-explorer:     $(svc_status TMDB)\n"
    TLDR+="    travel-http:       $(svc_status TRAVEL_HTTP)\n"
else
    TLDR+="  mb-health-monitor: ⚠️ state file missing ($MONITOR_STATE)\n"
    [ "$OK" -eq 1 ] && { OK=0; REASON="health monitor stale/missing"; }
fi

TLDR+="===================================================================\n\n"
BODY="${TLDR}${BODY}"

# --- Health monitor state (full dump, appended at the end) ---
BODY+="=== HEALTH MONITOR STATE ===\n"
if [ -f "$MONITOR_STATE" ]; then
    if [ -n "$MONITOR_ACTIVE" ]; then
        BODY+="ACTIVE ALERTS:\n$MONITOR_ACTIVE\n"
    else
        BODY+="No active alerts.\n"
    fi
    BODY+="\n$(cat "$MONITOR_STATE")\n"
else
    BODY+="⚠️ WARNING: state file not found — health monitor has not run\n"
fi

if [ "$OK" -eq 1 ]; then EMOJI="✅"; else EMOJI="⚠️"; fi
SUBJECT="${EMOJI} MacBook Air nightly $(date '+%Y-%m-%d') — ${REASON}"

{
    echo "Subject: $SUBJECT"
    # 2026-08-31 UTC — Cc self (dennis.mathes@icloud.com), nightly-summary only, never
    # the health-monitor alerts. That CC'd copy lands in the account's own INBOX
    # (confirmed via IMAP — iCloud doesn't auto-file SMTP-submitted mail to Sent), which
    # a separate daily digest script reads to report missing/not-ok boxes in one email.
    echo "Cc: dennis.mathes@icloud.com"
    echo ""
    echo -e "$BODY"
} | "$MSMTP" -a icloud "$TO" dennis.mathes@icloud.com
