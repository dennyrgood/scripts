#!/bin/sh
# Installs UPS power-event email on WorkBenchUnix. Created 2026-11-09 UTC.
# Run from the repo checkout as a normal user (it calls sudo itself):
#   sh WorkBenchUnix/install-nut-ups-mail.sh
set -e
cd "$(dirname "$0")"

echo "1. Validating sudoers snippet ..."
sudo visudo -cf nut-ups-mail.sudoers

echo "2. Installing helper, sudoers rule, and updated upssched-cmd ..."
sudo install -o root -g root -m 755 nut-ups-mail.sh      /etc/nut/ups-mail
sudo install -o root -g root -m 440 nut-ups-mail.sudoers /etc/sudoers.d/nut-ups-mail
sudo install -o root -g root -m 755 nut-upssched-cmd.sh  /etc/nut/upssched-cmd

echo "3. Test send as user nut (exactly the path upssched-cmd uses) ..."
sudo -u nut sudo -n /etc/nut/ups-mail online
echo "   Sent. Confirm with:  tail -1 /var/log/msmtp.log"
