#!/bin/bash
# UPS power-event mailer for WorkBenchUnix — installed to /etc/nut/ups-mail
# Created: 2026-11-09 UTC
#
# Called by /etc/nut/upssched-cmd as:  sudo -n /etc/nut/ups-mail <event>
#
# Why a separate root helper: upssched-cmd runs as user `nut`, but /etc/msmtprc
# is 600 root (it holds the SMTP password — see RUNBOOK_msmtp-credential-rotation.md).
# The sudoers rule (nut-ups-mail.sudoers) lets `nut` run exactly this file and
# nothing else. The event name is checked against a fixed list and the message is
# built here, so `nut` can't pass arbitrary mail content through.
#
# Only installed on WBU. upssched-cmd skips the mail if this file is absent, so the
# shared upssched-cmd stays safe to install on CWHU as-is.

EVENT="${1:-}"
TO="dennyrgood@yahoo.com"
HOST="$(hostname)"
UPS="ups2@localhost"

case "$EVENT" in
    onbatt)   SUBJECT="UPS ON BATTERY — shutdown timer started" ;;
    shutdown) SUBJECT="UPS SHUTTING DOWN — on-battery timer expired" ;;
    online)   SUBJECT="UPS power restored — shutdown cancelled" ;;
    *) logger -t ups-mail "Refusing unknown event '$EVENT'"; exit 2 ;;
esac

# Timer length read from the live config rather than hardcoded (see the comment
# on onbatt-shutdown in nut-upssched-cmd.sh for what a hardcoded figure cost).
TIMER="$(awk '$1=="AT" && $2=="ONBATT" && $4=="START-TIMER" {print $6}' /etc/nut/upssched.conf 2>/dev/null)"

{
    echo "To: $TO"
    echo "Subject: [${HOST}] ${SUBJECT} -- $(date '+%Y-%m-%d %H:%M')"
    echo ""
    echo "Event: $EVENT"
    [ -n "$TIMER" ] && echo "On-battery shutdown timer: ${TIMER}s ($((TIMER / 60)) min)"
    echo ""
    upsc "$UPS" 2>/dev/null | grep -E '^(ups\.status|battery\.charge|battery\.runtime|input\.voltage|ups\.load):' \
        || echo "(upsc $UPS unreadable)"
    echo ""
    echo "Log: journalctl -t upssched-cmd -t ups-mail -t nut-monitor"
} | msmtp --account=icloud "$TO"
rc=$?

logger -t ups-mail "Sent '$EVENT' mail to $TO (msmtp exit $rc)"
exit $rc
