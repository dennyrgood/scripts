#!/bin/bash
# add-s3g-probe-cron.sh -- add s3g_reachability_probe.sh to root's crontab.
# Created: 2026-10-24.
#
# Every 5 minutes. Same guards as add-syncthing-cron.sh: backs up first,
# refuses on a duplicate, verifies the entry landed and restores if it did not.
# Remove the entry once the s3g question is settled.

set -u

SCRIPT="/home/dhm/repos/scripts/WorkBenchUnix/s3g_reachability_probe.sh"
LOGFILE="/var/log/s3g-reachability.log"
CRON_LINE="*/5 * * * * $SCRIPT >/dev/null 2>>$LOGFILE"
STAMP=$(date +%Y-%m-%d_%H%M)
BACKUP="/root/crontab.bak.$STAMP"

fail() { echo; echo "FAILED: $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (use sudo)"
[ -x "$SCRIPT" ] || fail "$SCRIPT is missing or not executable"

echo "===== backing up current root crontab ====="
crontab -l > "$BACKUP" 2>/dev/null || fail "could not read root crontab"
chmod 0600 "$BACKUP"
echo "ok: $BACKUP ($(wc -l < "$BACKUP") lines)"

if grep -q "s3g_reachability_probe.sh" "$BACKUP"; then
    fail "crontab already references s3g_reachability_probe.sh -- nothing to do"
fi
echo "ok: no existing entry"

echo
echo "===== adding ====="
{
    cat "$BACKUP"
    echo ""
    echo "# --- s3g reachability probe (s3g vs GC router; mails when s3g returns) -- every 5 min ---"
    echo "# Added $STAMP. Temporary: remove once the s3g dropouts are explained."
    echo "$CRON_LINE"
} > /tmp/crontab.new.$$ || fail "could not build new crontab"

if ! crontab /tmp/crontab.new.$$; then
    rm -f /tmp/crontab.new.$$
    fail "crontab install failed -- the existing crontab is untouched"
fi
rm -f /tmp/crontab.new.$$

if ! crontab -l | grep -q "s3g_reachability_probe.sh"; then
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
