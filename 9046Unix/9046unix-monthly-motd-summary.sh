#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-monthly-motd-summary.sh
# 2026-11-09 03:25 UTC - monthly MOTD/system status email (same as WorkBenchUnix's);
# the login banner itself is hidden by ~/.hushlogin. Root cron (msmtp config is root-only).

TO="dennyrgood@yahoo.com"
SUBJECT="Monthly System Status - 9046unix - $(date '+%Y-%m-%d')"
BODY=$(cat /run/motd.dynamic)

{
    echo "To: $TO"
    echo "Subject: $SUBJECT"
    echo ""
    echo "$BODY"
} | msmtp "$TO"
