#!/bin/bash
# add-notes-to-self-cron.sh -- add notes_to_self_to_email.py to root's crontab.
# Created: 2026-10-24.
#
# Every minute. Same guards as add-s3g-probe-cron.sh: backs up first, refuses
# on a duplicate, verifies the entry landed and restores if it did not.
# Root, not dhm: msmtp's config (/etc/msmtprc) is root-only.

set -u

SCRIPT="/home/dhm/repos/scripts/WorkBenchUnix/notes_to_self_to_email.py"
LOGFILE="/var/log/notes-to-self.log"
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

if grep -q "notes_to_self_to_email.py" "$BACKUP"; then
    fail "crontab already references notes_to_self_to_email.py -- nothing to do"
fi
echo "ok: no existing entry"

echo
echo "===== adding ====="
{
    cat "$BACKUP"
    echo ""
    echo "# --- notes-to-self -> Yahoo (iMessages you text yourself, read from FleetDev's Messages) -- every minute ---"
    echo "# Added $STAMP."
    echo "$CRON_LINE"
} > /tmp/crontab.new.$$ || fail "could not build new crontab"

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
echo "===== first run (records where to start; mails nothing) ====="
"$SCRIPT" && tail -1 "$LOGFILE"
echo
echo "Now text yourself something; it should reach $(grep -oP '(?<=^TO = ")[^"]+' "$SCRIPT") within a minute or two."
echo "backup: $BACKUP"
echo "To undo:  sudo crontab $BACKUP"
