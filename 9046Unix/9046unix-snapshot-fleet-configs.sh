#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-snapshot-fleet-configs.sh
# 2026-11-08 — created. Copies 9046unix's live rebuild/recovery files into the
# fleet-configs repo snapshot (~/repos/fleet-configs/9046unix). Run as dhm on the box
# (calls sudo itself; this box has passwordless sudo).
# Manual-run only: review `git status` / `git diff` and commit yourself afterwards.
# README.md in that directory is hand-written and is NOT touched here.

set -e
DEST=~/repos/fleet-configs/9046unix
mkdir -p "$DEST"

cp -p /etc/fstab "$DEST/fstab.txt"
cp -p /etc/smartd.conf "$DEST/smartd.conf"
cp -p /etc/aliases "$DEST/etc-aliases"
cp -p /etc/logrotate.d/msmtp "$DEST/logrotate-msmtp"
cp -p /etc/systemd/system/fleet_metrics_server.service "$DEST/fleet_metrics_server.service"

# msmtprc WITHOUT its password line. Excludes lines rather than rewriting them
# (a rewrite that fails to match would print the secret).
sudo grep -viE '^[[:space:]]*password' /etc/msmtprc > "$DEST/msmtprc.no-password"

crontab -l > "$DEST/crontab-l-dhm.txt" 2>&1 || true
sudo crontab -l > "$DEST/crontab-l-root.txt"
cp -p ~/.ssh/authorized_keys "$DEST/ssh-authorized_keys.txt"

{
    grep -E '^HandleLid' /etc/systemd/logind.conf
    echo
    for s in cups.service cups.socket cups.path cups-browsed.service bluetooth.service \
             ModemManager.service avahi-daemon.service avahi-daemon.socket \
             multipathd.service multipathd.socket sleep.target suspend.target \
             hibernate.target hybrid-sleep.target fleet_metrics_server.service \
             smartmontools.service; do
        echo "$s $(systemctl is-enabled "$s" 2>&1)"
    done
} > "$DEST/systemd-state.txt"

{
    lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINT,MODEL
    echo
    ls -l /dev/disk/by-id/ | grep -E 'usb-|ata-' | awk '{print $9, $10, $11}'
} > "$DEST/disks.txt"

echo "Snapshot complete. Review with: cd $DEST && git status"
