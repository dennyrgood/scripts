#!/bin/bash
# add-s3g-probe-cron.sh -- add s3g_reachability_probe.sh to root's crontab.
# Created: 2026-10-24.
#
# Every minute (was */5 until 2026-10-24). Same guards as add-syncthing-cron.sh: backs up first,
# refuses on a duplicate, verifies the entry landed and restores if it did not.
# Remove the entry once the s3g question is settled.

set -u

SCRIPT="/home/dhm/repos/scripts/WorkBenchUnix/s3g_reachability_probe.sh"
LOGFILE="/var/log/s3g-reachability.log"
CRON_LINE="* * * * * $SCRIPT >/dev/null 2>>$LOGFILE"
STAMP=$(date +%Y-%m-%d_%H%M)
BACKUP="/root/crontab.bak.$STAMP"

fail() { echo; echo "FAILED: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (use sudo)"
[ -x "$SCRIPT" ] || fail "$SCRIPT is missing or not executable"

echo "===== backing up current root crontab ====="
crontab -l > "$BACKUP" 2>/dev/null || fail "could not read root crontab"
chmod 0600 "$BACKUP"
echo "ok: $BACKUP ($(wc -l < "$BACKUP") lines)"

# An existing entry with a different schedule (the original */5) is swapped
# for CRON_LINE in place; an identical one means there is nothing to do.
if grep -qxF "$CRON_LINE" "$BACKUP"; then
    fail "crontab already has this exact entry -- nothing to do"
fi
if grep -q "s3g_reachability_probe.sh" "$BACKUP"; then
    echo "ok: existing entry found -- changing its schedule"
    echo
    echo "===== updating ====="
    awk -v new="$CRON_LINE" '/^[^#].*s3g_reachability_probe\.sh/ {print new; next} {print}' "$BACKUP" \
        > /tmp/crontab.new.$$ || fail "could not build new crontab"
    sed -i 's/(s3g vs GC router; mails when s3g returns) -- every 5 min ---/(s3g vs GC router; mails when s3g returns) -- every minute ---/' /tmp/crontab.new.$$
else
    echo "ok: no existing entry"

    echo
    echo "===== adding ====="
    {
        cat "$BACKUP"
        echo ""
        echo "# --- s3g reachability probe (s3g vs GC router; mails when s3g returns) -- every minute ---"
        echo "# Added $STAMP. Temporary: remove once the s3g dropouts are explained."
        echo "$CRON_LINE"
    } > /tmp/crontab.new.$$ || fail "could not build new crontab"
fi

if ! crontab /tmp/crontab.new.$$; then
    rm -f /tmp/crontab.new.$$
    fail "crontab install failed -- the existing crontab is untouched"
fi
rm -f /tmp/crontab.new.$$

if ! crontab -l | grep -qxF "$CRON_LINE"; then
    echo "!! entry not present after install -- restoring backup"
    crontab "$BACKUP"
    fail "verification failed; crontab restored from $BACKUP"
fi
echo "ok: entry installed"

echo
echo "===== first probe ====="
"$SCRIPT" && tail -1 "$LOGFILE"
echo
echo "backup: $BACKUP"
echo "To undo:  sudo crontab $BACKUP"
