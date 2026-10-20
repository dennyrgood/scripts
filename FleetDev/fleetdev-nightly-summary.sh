#!/bin/bash
# Created: 2026-08-30 UTC (cloned to FleetDev 2026-09-18) — daily health summary email
# for FleetDev, modeled on MathesMacMini/nightly_summary.sh but scoped to what actually
# runs on THIS box. No UPS/Plex/Syncthing sections — none of that runs here. The one
# scheduled (non-KeepAlive) job on this box, comfy-fleet-scan (daily 05:00), gets
# its own freshness check here, the same role mmm's nightly script gives the Plex
# sync log — fleetdev-health-monitor.sh deliberately excludes it since a once-daily
# StartCalendarInterval job is "missing" 23:55 hours a day by design.
#
# Sends via msmtp (iCloud SMTP, ~/.msmtprc) — see the mmm/WBU runbooks under
# WorkBenchUnix/RUNBOOK_msmtp-credential-rotation.md for credential setup/rotation.
# Run via launchd, which gets a minimal PATH, so msmtp is called by full Homebrew
# path throughout.

MSMTP="/opt/homebrew/bin/msmtp"
TO="dennyrgood@yahoo.com"
HOST="fleetdev"
LINES=10
MONITOR_STATE="/tmp/fleetdev-monitor-state.tmp"
# 2026-09-04: briefly padded to 43200s (12h) after the identical bug surfaced on mb2
# (StartInterval launchd jobs don't fire/catch up during sleep, so a normal overnight
# sleep alone falsely flagged mb-health-monitor as stale). Reverted to a tight-ish
# threshold on the understanding that mb, like mb2, is always on AC power with the lid
# never closed and should also get `sudo pmset -a sleep 0 standby 0 powernap 0` run on
# it directly (that command was run on mb2 as part of this fix — confirm/run it on mb
# too if not already done). Padded a bit past the 5-min run interval to absorb ordinary
# scheduling jitter, not to ride out sleep.
MONITOR_STALE_SECS=1800   # 30 min (6x the 5-min run interval)

# 2026-10-20 20:07 UTC: money (~/repos/money), FleetDev as its read-only standby until cutover: `money health` (the web
# app, the books, the copy from mb arrived and put in place) and the 06:30 copy to FleetNAS (its log ends "=== done ===").
# `money health` follows the role: after cutover it reports FleetDev's fetches, backups and its copy-off to mb instead.
# The NAS check runs only while com.dennis.money-copy-to-nas is loaded: at cutover FleetDev's own copy-off
# ([copy.fleetnas]) replaces it, and `money health` reports that copy.
MONEY_REPO="$HOME/repos/money"
NAS_LOG="$HOME/Library/Logs/money_copy_to_nas.log"
NAS_STALE_SECS=93600     # 26h: a daily 06:30 job
# 2026-10-20 20:07 UTC: the send is tried again every 10 minutes for an hour (msmtp gives up at once when offline, exit 75).
SEND_TRIES=7
SEND_WAIT_SECS=600

SCAN_LOG="$HOME/Library/Logs/comfy_fleet_scan.log"
SCAN_STALE_SECS=115200   # 32h — scan fires 05:00, nightly summary runs a few hours
                         # later at 07:00; padded well past 24h so a single missed
                         # day doesn't look identical to two missed days, matching
                         # mmm's reasoning for its own padded threshold.

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

# --- comfy-fleet-scan freshness ---
# 2026-08-30: scan log content is untrusted (it's Windows paths from remote SSH
# output, e.g. "...MathesDropBox\0ComfyUI\Work...") and gets embedded into BODY,
# which is later rendered with `echo -e` further down. A raw backslash there is
# not just cosmetic: echo -e treats "\0" as a literal NUL-byte escape, and a NUL
# mid-body silently truncates the email for most mail clients/renderers -- the
# UPS-analog section and the full state dump below never even made it out.
# Doubling backslashes here defuses that before it reaches echo -e.
BODY+="=== $SCAN_LOG ===\n"
if [ -f "$SCAN_LOG" ]; then
    BODY+="$(tail -$LINES "$SCAN_LOG" | sed 's/\\/\\\\/g')\n"
else
    BODY+="(file not found)\n"
fi
BODY+="\n"

SCAN_TLDR=""
if [ -f "$SCAN_LOG" ]; then
    SCAN_AGE_SECS=$(( $(date +%s) - $(stat -f %m "$SCAN_LOG") ))
    SCAN_AGE=$(fmt_age "$SCAN_AGE_SECS")
    SCAN_TLDR="  comfy-fleet-scan: [${SCAN_AGE} ago] $(tail -1 "$SCAN_LOG" | sed 's/\\/\\\\/g')"
    if [ "$OK" -eq 1 ] && [ "$SCAN_AGE_SECS" -gt "$SCAN_STALE_SECS" ]; then
        OK=0; REASON="comfy-fleet-scan log stale (${SCAN_AGE})"
        SCAN_TLDR="⚠️${SCAN_TLDR}"
    fi
else
    SCAN_TLDR="  comfy-fleet-scan: ⚠️ log not found"
    [ "$OK" -eq 1 ] && { OK=0; REASON="comfy-fleet-scan log missing — launchd may not have run it yet"; }
fi

# --- Health monitor watchdog (freshness + active alerts) in TLDR ---
TLDR="============================= TLDR ===============================\n"
TLDR+="${SCAN_TLDR}\n"
if [ -f "$MONITOR_STATE" ]; then
    MONITOR_AGE=$(( $(date +%s) - $(stat -f %m "$MONITOR_STATE") ))
    if [ "$MONITOR_AGE" -gt "$MONITOR_STALE_SECS" ]; then
        TLDR+="  fleetdev-health-monitor: ⚠️ stale (last-run $((MONITOR_AGE / 60))m ago; threshold $((MONITOR_STALE_SECS / 60))m)\n"
        [ "$OK" -eq 1 ] && { OK=0; REASON="health monitor stale/missing"; }
    else
        TLDR+="  fleetdev-health-monitor: last-run $((MONITOR_AGE / 60))m ago ✓\n"
    fi
    MONITOR_ACTIVE=$(grep "_ACTIVE=1" "$MONITOR_STATE" 2>/dev/null)
    if [ -n "$MONITOR_ACTIVE" ]; then
        TLDR+="  fleetdev-health-monitor: ⚠️ active alerts\n"
        [ "$OK" -eq 1 ] && { OK=0; REASON="active health alerts"; }
    else
        TLDR+="  fleetdev-health-monitor: no active alerts ✓\n"
    fi
    TLDR+="    comfy-fleet-http:  $(svc_status COMFY_HTTP)\n"
    TLDR+="    metrics-server:    $(svc_status METRICS_SERVER)\n"
    TLDR+="    heartbeat-writer:  $(svc_status HEARTBEAT_WRITER)\n"
    TLDR+="    search-adv-web:    $(svc_status SEARCH_ADV)\n"
    TLDR+="    search-shows-web:  $(svc_status SEARCH_SHOWS)\n"
    TLDR+="    tmdb-explorer:     $(svc_status TMDB)\n"
    TLDR+="    travel-http:       $(svc_status TRAVEL_HTTP)\n"
else
    TLDR+="  fleetdev-health-monitor: ⚠️ state file missing ($MONITOR_STATE)\n"
    [ "$OK" -eq 1 ] && { OK=0; REASON="health monitor stale/missing"; }
fi

# --- money: the standby and its copy to FleetNAS ---
if [ -x "$MONEY_REPO/.venv/bin/money" ]; then
    MONEY_OUT=$("$MONEY_REPO/.venv/bin/money" --config "$MONEY_REPO/config.toml" health 2>&1)
    MONEY_RC=$?
    TLDR+="  money:\n$(printf '%s\n' "$MONEY_OUT" | sed 's/^/    /')\n"
    if [ "$MONEY_RC" -ne 0 ] && [ "$OK" -eq 1 ]; then
        OK=0
        REASON="money: $(printf '%s\n' "$MONEY_OUT" | grep -m1 -E '^(FAIL|WARN)' | sed -E 's/^(FAIL|WARN) +//; s/:.*//')"
        [ "$REASON" = "money: " ] && REASON="money: health check failed"
    fi
else
    TLDR+="  money: ⚠️ no $MONEY_REPO/.venv/bin/money\n"
    [ "$OK" -eq 1 ] && { OK=0; REASON="money: not installed"; }
fi
if ! launchctl print "gui/$(id -u)/com.dennis.money-copy-to-nas" >/dev/null 2>&1; then
    :                                            # not this Mac's job (any more): money health covers the copies
elif [ -f "$NAS_LOG" ]; then
    NAS_AGE=$(( $(date +%s) - $(stat -f %m "$NAS_LOG") ))
    NAS_LAST=$(tail -1 "$NAS_LOG")
    if [ "$NAS_AGE" -gt "$NAS_STALE_SECS" ]; then
        TLDR+="    FAIL  copy to FleetNAS: no run for $(fmt_age "$NAS_AGE")\n"
        [ "$OK" -eq 1 ] && { OK=0; REASON="money: copy to FleetNAS stale"; }
    elif [[ "$NAS_LAST" == *"=== done ==="* ]]; then
        TLDR+="    OK    copy to FleetNAS: done $(fmt_age "$NAS_AGE") ago, newest snapshots hash-checked\n"
    else
        TLDR+="    FAIL  copy to FleetNAS: $(grep -E 'FAIL|WARN' "$NAS_LOG" | tail -1 | sed -E 's/^\[[^]]*\] //')\n"
        [ "$OK" -eq 1 ] && { OK=0; REASON="money: copy to FleetNAS failed"; }
    fi
else
    TLDR+="    FAIL  copy to FleetNAS: no log yet ($NAS_LOG)\n"
    [ "$OK" -eq 1 ] && { OK=0; REASON="money: copy to FleetNAS never ran"; }
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
SUBJECT="${EMOJI} FleetDev nightly $(date '+%Y-%m-%d') — ${REASON}"

MESSAGE=$({
    echo "Subject: $SUBJECT"
    # 2026-08-31 UTC — Cc self (dennis.mathes@icloud.com), nightly-summary only, never
    # the health-monitor alerts. That CC'd copy lands in the account's own INBOX
    # (confirmed via IMAP — iCloud doesn't auto-file SMTP-submitted mail to Sent), which
    # a separate daily digest script reads to report missing/not-ok boxes in one email.
    echo "Cc: dennis.mathes@icloud.com"
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
