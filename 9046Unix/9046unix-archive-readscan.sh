#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-archive-readscan.sh
# 2026-11-08 — created.
#
# Monthly full-surface READ-ONLY scan of archive02s, emailing the result.
# 02s sits in a Seagate Expansion enclosure that blocks SMART, so smartd can't run
# self-tests on it; reading every sector is the substitute. A sector that has gone
# bad shows up here (and as kernel I/O errors, which the health monitor reports)
# instead of when you need the backup.
#
# Read-only badblocks is safe on a mounted filesystem. ~4.5 TB over USB takes
# roughly 8-12 hours; it runs at idle I/O priority. Runs from ROOT's crontab.
#
# Usage: 9046unix-archive-readscan.sh [by-id-device] [label]

DEV="${1:-/dev/disk/by-id/usb-Seagate_Expansion_Desk_NA8FGSM6-0:0}"
LABEL="${2:-archive02s (W4J1XARP)}"
TO="dennyrgood@yahoo.com"
HOST="9046unix"
LOG="/var/log/9046unix-readscan.log"
BAD=$(mktemp)
trap 'rm -f "$BAD"' EXIT

START=$(date +%s)
echo "$(date '+%F %T') start $LABEL $DEV" >> "$LOG"

if [ ! -b "$DEV" ]; then
    RESULT="FAILED: $DEV not present"
else
    OUTF=$(mktemp)
    ionice -c3 nice -n 19 badblocks -b 4096 -c 1024 -o "$BAD" "$DEV" > "$OUTF" 2>&1
    RC=$?
    OUT=$(tail -3 "$OUTF"); rm -f "$OUTF"
    NBAD=$(wc -l < "$BAD")
    if [ "$NBAD" -eq 0 ] && [ $RC -eq 0 ]; then
        RESULT="OK: 0 bad blocks"
    else
        RESULT="BAD BLOCKS FOUND: $NBAD (rc=$RC)"
    fi
fi

MINS=$(( ($(date +%s) - START) / 60 ))
echo "$(date '+%F %T') end   $LABEL: $RESULT (${MINS} min)" >> "$LOG"

{
    echo "To: $TO"
    echo "Subject: [${HOST}] read scan ${LABEL}: ${RESULT}"
    echo ""
    echo "Device:   $DEV ($(readlink -f "$DEV" 2>/dev/null))"
    echo "Result:   $RESULT"
    echo "Duration: ${MINS} min"
    echo ""
    [ -n "$OUT" ] && echo "$OUT" && echo ""
    if [ -s "$BAD" ]; then
        echo "First bad 4K blocks:"; head -20 "$BAD"; echo ""
        echo "Bad blocks on a backup drive: copy what matters elsewhere and plan to replace it."
    fi
    echo "History ($LOG):"
    tail -6 "$LOG"
} | msmtp "$TO"
