#!/bin/bash
# msmtp-pass-to-file.sh -- copy FleetDev's iCloud SMTP password from the login
# keychain into ~/.msmtp-icloud.pass (mode 600) so msmtp works from ssh and
# launchd too, where the keychain is not readable ("User interaction is not
# allowed"). ~/.msmtprc's passwordeval reads this file first, keychain second.
# Created: 2026-10-24. Run once, in a Terminal on FleetDev's own desktop.
# Prints nothing secret.
set -u
F=~/.msmtp-icloud.pass
umask 077
security find-generic-password -a dennis.mathes@icloud.com -s msmtp-denniss-macbook-air -w > "$F" || { rm -f "$F"; echo "FAILED: keychain read"; exit 1; }
chmod 600 "$F"
echo "ok: $F written ($(wc -c < "$F" | tr -d ' ') bytes, mode $(stat -f %Lp "$F"))"
printf 'To: dennyrgood@yahoo.com\nSubject: fd msmtp test\n\nmsmtp works without the keychain now.\n' | /opt/homebrew/bin/msmtp --account=icloud dennyrgood@yahoo.com && echo "ok: test email sent"
