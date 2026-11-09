#!/bin/sh
# /home/dhm/repos/scripts/9046Unix/test-mail.sh   (2026-11-09 04:05 UTC - moved into the repo from ~/test-mail.sh, created 2026-11-07)
# Send a test mail to root (aliased to Yahoo) and show the msmtp log result.
printf "Subject: [%s] msmtp test\n\nIf this arrives, 9046unix mail works.\n" "$(hostname)" | sudo /usr/sbin/sendmail -i root
tail -1 /var/log/msmtp.log
