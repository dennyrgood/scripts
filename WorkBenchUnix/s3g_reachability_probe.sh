#!/bin/bash
# s3g_reachability_probe.sh -- every minute: is s3g up, and does the Gran
# Canaria router answer? Emails when s3g comes back after an outage.
# Created: 2026-10-24.
#
# WHY THIS EXISTS
#   Since 2026-10-20 s3g has been reachable only in short sessions, often
#   ending ~60 min after they start. From wbu a sleeping Surface and a dead GC
#   link look identical. The router's public IP is a third observer: logged
#   side by side with s3g's state, it separates them --
#     router answers while s3g is gone   -> link is fine, the box is asleep/off
#     router goes silent with s3g        -> the link (or power at the house)
#     router never answers, even with s3g up -> it drops ping; this tells nothing
#
#   The router IP is learned from Tailscale's direct-path endpoint whenever s3g
#   is online, so a changed public IP (itself a clue: router reboot) is followed.
#
#   It also mails when s3g comes back, because work on s3g (e.g. running
#   Surface3GC/s3g-why-offline.ps1) needs it up, and it rarely stays up long.
#   When that script's output appears on s3g's :9100 it is copied here.
#
# Runs from ROOT's crontab (add-s3g-probe-cron.sh): msmtp's config is root-only.

set -u

S3G_TS_IP="100.72.84.84"
LOG="/var/log/s3g-reachability.log"
STATE="/var/lib/s3g-reachability.state"
FORENSICS_URL="http://$S3G_TS_IP:9100/watchdog_s3g-why-offline_surface3-gc.txt"
FORENSICS_DIR="/var/log/s3g-why-offline"
TO="dennyrgood@yahoo.com"
# A blip is not an outage worth a mail; 10 minutes of misses is.
NOTIFY_MIN_DOWN_MIN=10

# iMessage alongside the mail: sessions can be minutes long, and a mail read
# 25 min later misses them (2026-10-24 12:51Z: up <2 min). wbu cannot send
# iMessage itself, so FleetDev's Messages.app does it over ssh as dhm (root
# has no key there). Messages is signed in as the same Apple ID as the
# phone, so this is a note-to-self; tests to both dennyrgood@yahoo.com and
# dennis.mathes@icloud.com arrived (2026-10-24). The mail stays the fallback.
IMSG_HOST="dennishmathes@fleetdev"
IMSG_TO="dennyrgood@yahoo.com"
IMSG_ACCOUNT="66EA877A-3C36-4C47-B8F3-351954AB6DB9"   # FleetDev Messages, E:dennyrgood@yahoo.com

[ "$(id -u)" -eq 0 ] || { echo "FAILED: run as root (msmtp config is root-only)"; exit 1; }

# Every minute, and a run with s3g down takes ~15s (up to ~40s fetching the
# report): the lock makes a slow run skip the next one rather than overlap it.
exec 9>/run/s3g-reachability.lock
flock -n 9 || exit 0

TEST=""; [ "${1:-}" = "--test" ] && TEST=1
IP_CHANGED=""; ROUTER="(not probed)"

NOW=$(date -u +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PREV=""; DOWN_SINCE=""; ROUTER_IP=""; FORENSICS_SUM=""
if [ -r "$STATE" ]; then
    PREV=$(grep -oP '(?<=^S3G=).*' "$STATE" | head -1)
    DOWN_SINCE=$(grep -oP '(?<=^DOWN_SINCE=).*' "$STATE" | head -1)
    ROUTER_IP=$(grep -oP '(?<=^ROUTER_IP=).*' "$STATE" | head -1)
    FORENSICS_SUM=$(grep -oP '(?<=^FORENSICS_SUM=).*' "$STATE" | head -1)
fi
# Seed: s3g's direct endpoint as seen 2026-10-24 (Airtel ES).
[ -n "$ROUTER_IP" ] || ROUTER_IP="87.125.128.148"

# The comeback mail. A function so --test can send exactly what a real
# return would, without probing or touching the log/state.
# Never allowed to delay or block the mail: short timeout, errors logged only.
# The AppleScript goes over ssh stdin, so nothing has to be installed on FleetDev.
send_back_imessage() {
    local text="${1//\'/}"
    timeout 30 sudo -u dhm ssh -o BatchMode=yes -o ConnectTimeout=10 "$IMSG_HOST" \
        osascript - "$IMSG_TO" "'$text'" >/dev/null 2>&1 <<APPLESCRIPT
on run argv
    tell application "Messages"
        send (item 2 of argv) to participant (item 1 of argv) of account id "$IMSG_ACCOUNT"
    end tell
end run
APPLESCRIPT
    local rc=$?
    [ "$rc" -eq 0 ] || echo "[$NOW_ISO] iMessage via $IMSG_HOST failed (rc=$rc)" >> "$LOG"
    return "$rc"
}

send_back_mail() {
    # What the router did while s3g was away -- the whole point of the probe.
    OUTAGE=$(awk -v s="[$DOWN_SINCE]" '$1 >= s && /s3g=down/' "$LOG" 2>/dev/null)
    R_YES=$(printf '%s\n' "$OUTAGE" | grep -c 'ping=yes')
    R_NO=$(printf '%s\n' "$OUTAGE" | grep -c 'ping=no')
    if   [ "$R_YES" -gt 0 ] && [ "$R_NO" -eq 0 ]; then VERDICT="router answered throughout -> link was up; points at the BOX (asleep/off)"
    # Silence during the outage only means something if the router answers
    # when s3g is up -- many ISP routers drop WAN ping by design. $ROUTER is
    # this run's ping, taken with s3g just back.
    elif [ "$ROUTER" = "yes" ]; then VERDICT="router silent throughout, but answers now that s3g is back -> the LINK (or power at the house) was down"
    elif [ "$ROUTER" = "no" ]; then VERDICT="router silent throughout AND silent now with s3g up -> it drops ping by design; tells nothing -- the s3g event log is the only answer"
    elif [ "$R_YES" -eq 0 ]; then VERDICT="router silent throughout; not probed now (--test), so no baseline"
    else VERDICT="router answered $R_YES of $((R_YES + R_NO)) probes -- mixed; see the log"
    fi
    H=$(( DOWN_MIN / 60 )); M=$(( DOWN_MIN % 60 ))
    {
        echo "To: $TO"
        echo "Subject: [wbu] ${TEST:+[TEST] }s3g is back online (was down ${H}h${M}m)"
        echo ""
        echo "s3g answered a Tailscale ping at $NOW_ISO (path: $PATH_TXT)."
        echo "Down since $DOWN_SINCE (${H}h${M}m)."
        echo ""
        echo "GC router $ROUTER_IP during the outage: $VERDICT"
        echo "GC router right now, with s3g up: answers ping=$ROUTER"
        [ -n "$IP_CHANGED" ] && echo "GC public IP changed on return ($IP_CHANGED): the router restarted or reconnected -> points at the LINK/power, not the Surface"
        echo ""
        cat <<'STEPS'
WHAT TO DO ON s3g -- now; recent sessions often last only ~1h
------------------------------------------------------------
Nothing gets installed and nothing changes on s3g; this only reads the
event log and writes one report file.

1. Remote into s3g (surface3-gc).

2. Open an ADMIN PowerShell:
   Start -> type "powershell" -> right-click "Windows PowerShell"
   -> "Run as administrator" -> Yes.
   (Admin is needed only for the battery report; the rest works without.)

3. Get the script (it lives in the scripts repo):
   cd C:\repos\scripts
   git pull
   Expect Surface3GC\s3g-why-offline.ps1 among the pulled files.

4. Run it (takes under a minute):
   .\Surface3GC\s3g-why-offline.ps1
   If PowerShell refuses with "running scripts is disabled", use:
   powershell -ExecutionPolicy Bypass -File .\Surface3GC\s3g-why-offline.ps1

5. That's it. It writes
   C:\fleet_monitor\watchdog_s3g-why-offline_surface3-gc.txt
   and wbu's probe copies it within a minute or two to /var/log/s3g-why-offline/
   on wbu. Optional while you're there: open
   C:\fleet_monitor\battery-report.html
   and look at "Recent usage" (AC vs Battery, Active vs Suspended).

Quick things to eyeball while connected:
   - battery icon in the taskbar: plugged in and charging, or on battery?
   - Settings -> System -> Power & sleep: "When plugged in, PC goes to
 sleep after" should be Never.
STEPS
        echo ""
        echo "Last 12 probes ($LOG):"
        tail -12 "$LOG" 2>/dev/null
    } | msmtp --account=icloud "$TO"
}

# --test: send the comeback mail now with current data, change nothing.
#   sudo ./s3g_reachability_probe.sh --test
if [ -n "$TEST" ]; then
    S3G=up; PATH_TXT="(test -- not probed)"
    [ -n "$DOWN_SINCE" ] || DOWN_SINCE=$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)
    DOWN_MIN=$(( (NOW - $(date -u -d "$DOWN_SINCE" +%s)) / 60 ))
    send_back_imessage "[TEST] s3g is back online (was down $((DOWN_MIN / 60))h$((DOWN_MIN % 60))m). Jump Desktop in now; steps in the email." \
        && echo "test iMessage sent to $IMSG_TO via $IMSG_HOST" || echo "FAILED: iMessage via $IMSG_HOST (see $LOG)"
    send_back_mail && echo "test mail sent to $TO" || echo "FAILED: msmtp returned an error"
    exit 0
fi

# --- s3g ------------------------------------------------------------------------
# tailscale ping, not the control plane's Online flag: that lags by minutes.
S3G=down; PATH_TXT="-"
PONG=$(tailscale ping -c 2 --timeout 5s "$S3G_TS_IP" 2>/dev/null | grep -m1 '^pong') && S3G=up
if [ "$S3G" = "up" ]; then
    # "pong from surface3-gc (100.72.84.84) via 87.125.128.148:20095 in 52ms"
    # or "... via DERP(mad) in 120ms"
    VIA=$(printf '%s' "$PONG" | grep -oP '(?<= via )\S+')
    case "$VIA" in
        DERP*) PATH_TXT="relay:$VIA" ;;
        *)     PATH_TXT="direct"
               NEW_IP=${VIA%:*}
               if printf '%s' "$NEW_IP" | grep -qP '^\d+\.\d+\.\d+\.\d+$' \
                  && ! printf '%s' "$NEW_IP" | grep -qP '^(10|127|192\.168|172\.(1[6-9]|2\d|3[01])|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.'; then
                   if [ "$NEW_IP" != "$ROUTER_IP" ]; then
                       echo "[$NOW_ISO] router public IP changed: $ROUTER_IP -> $NEW_IP" >> "$LOG"
                       IP_CHANGED="$ROUTER_IP -> $NEW_IP"
                   fi
                   ROUTER_IP="$NEW_IP"
               fi ;;
    esac
fi

# --- GC router ------------------------------------------------------------------
ping -c 3 -W 2 -q "$ROUTER_IP" >/dev/null 2>&1 && ROUTER=yes || ROUTER=no

echo "[$NOW_ISO] s3g=$S3G path=$PATH_TXT router=$ROUTER_IP ping=$ROUTER" >> "$LOG"

# --- transitions ----------------------------------------------------------------
if [ "$S3G" = "down" ]; then
    if [ "$PREV" != "down" ] || [ -z "$DOWN_SINCE" ]; then
        DOWN_SINCE="$NOW_ISO"
        # First run with s3g already down: Tailscale's last-seen is closer to
        # the truth than "when this probe was installed".
        if [ -z "$PREV" ]; then
            LS=$(tailscale status --json 2>/dev/null | python3 -c "
import sys,json
for v in json.load(sys.stdin).get('Peer',{}).values():
    if '$S3G_TS_IP' in (v.get('TailscaleIPs') or []): print((v.get('LastSeen') or '')[:19]+'Z')
" 2>/dev/null)
            [ -n "$LS" ] && [ "$LS" != "Z" ] && DOWN_SINCE="$LS"
        fi
    fi
elif [ "$PREV" = "down" ] && [ -n "$DOWN_SINCE" ]; then
    DOWN_MIN=$(( (NOW - $(date -u -d "$DOWN_SINCE" +%s)) / 60 ))
    if [ "$DOWN_MIN" -ge "$NOTIFY_MIN_DOWN_MIN" ]; then
        # iMessage first: it is the one meant to be seen within the minute.
        send_back_imessage "s3g is back online (was down $((DOWN_MIN / 60))h$((DOWN_MIN % 60))m). Jump Desktop in now; steps in the email."
        send_back_mail
    fi
    DOWN_SINCE=""
fi

# --- s3g's own evidence, when it publishes it -------------------------------------
if [ "$S3G" = "up" ]; then
    F=$(curl -sf --max-time 20 "$FORENSICS_URL" 2>/dev/null) && {
        SUM=$(printf '%s' "$F" | sha256sum | cut -c1-16)
        if [ "$SUM" != "$FORENSICS_SUM" ]; then
            mkdir -p "$FORENSICS_DIR"
            printf '%s\n' "$F" > "$FORENSICS_DIR/s3g-why-offline_$(date -u +%Y%m%d_%H%MZ).txt"
            echo "[$NOW_ISO] fetched new s3g-why-offline output into $FORENSICS_DIR" >> "$LOG"
            FORENSICS_SUM="$SUM"
        fi
    }
fi

mkdir -p "$(dirname "$STATE")"
printf 'S3G=%s\nDOWN_SINCE=%s\nROUTER_IP=%s\nFORENSICS_SUM=%s\n' \
    "$S3G" "$DOWN_SINCE" "$ROUTER_IP" "$FORENSICS_SUM" > "$STATE"
