#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-health-monitor.sh
# 2026-11-08 — created, modelled on ChatWorkhorseUnix/cwhu-health-monitor.sh.
#
# 9046UNIX system health monitor. Runs every 5 minutes from ROOT's crontab
# (needs root: msmtp config is root-only, journalctl -k, shutdown).
# Checks: iowait, D-state processes, disk usage, archive mounts (marker file +
# read-write), ext4 error counts, kernel disk I/O errors, AC power / battery.
# Emails on first detection and every 30 minutes while a condition persists,
# sends an all-clear when it resolves. No email if all healthy.
#
# Why the archive checks matter: the three 5TB archive drives are USB and mounted
# with `nofail`. If one drops off the bus, its mount point becomes a plain empty
# directory on the root SSD and a backup job would happily fill the SSD instead.
# Jobs should refuse to run without the marker file; this monitor tells you when
# a drive is gone. 02s (Seagate Expansion enclosure) blocks SMART entirely, so the
# kernel-I/O-error and ext4-error checks are the only live health signal for it
# (plus the monthly read scan, 9046unix-archive-readscan.sh).

HOST="9046unix"
TO="dennyrgood@yahoo.com"
STATE_FILE="/var/tmp/9046unix-monitor-state.tmp"
NOW=$(date +%s)
ALERT_INTERVAL=$((30 * 60))

IOWAIT_THRESHOLD=20
DISK_THRESHOLD=85
DSTATE_FAIL_THRESHOLD=2

ARCHIVES=(archive00p archive01p archive02s)   # under /mnt; each has a .archive-mounted marker
MARKER=".archive-mounted"

# Battery: the laptop battery keeps the box itself up on a power cut, but the 3.5"
# archive drives have their own power bricks and drop immediately unless those
# bricks are on a UPS. So the AC-loss alert is mainly "power is out"; the low-battery
# shutdown just keeps the OS disk clean.
AC_ONLINE_FILE="/sys/class/power_supply/ADP1/online"
BAT_CAP_FILE="/sys/class/power_supply/BAT0/capacity"
BAT_SHUTDOWN_PCT=20

# --- Load state ---
IOWAIT_LAST_ALERT=0; IOWAIT_ACTIVE=0
DSTATE_LAST_ALERT=0; DSTATE_ACTIVE=0; DSTATE_STREAK=0
DISK_LAST_ALERT=0;   DISK_ACTIVE=0
EXT4ERR_LAST_ALERT=0; EXT4ERR_ACTIVE=0
ONBATTERY_LAST_ALERT=0; ONBATTERY_ACTIVE=0
SHUTDOWN_SENT=0
LAST_RUN=$((NOW - 300))
for a in "${ARCHIVES[@]}"; do eval "MOUNT_${a}_LAST_ALERT=0; MOUNT_${a}_ACTIVE=0"; done

[ -f "$STATE_FILE" ] && source "$STATE_FILE"

# One run at a time: an auto-remount (fsck) can outlast the 5-minute cron interval.
exec 9>/run/9046unix-health-monitor.lock
flock -n 9 || exit 0

ALERT_BODY=""
CLEAR_BODY=""

# --- Check 0: archive auto-remount after a power cut / USB drop (added 2026-11-08) ---
# The archive drives run off their own power bricks, the laptop off its battery. In a
# power cut the drives vanish from USB and systemd unmounts them (tested 2026-11-08 by
# unbinding 02s's USB device), leaving the bare mount-point directory on the root SSD --
# which is why backup jobs must check the marker file. When power returns the drive
# reappears but nothing remounts it. So: if a drive's UUID is present but its mount is
# missing, points at an old device, or is dead, then lazy-unmount (if needed), fsck
# (preen only; replays the journal), mount from fstab, and report.
REMOUNT_LOG="/var/log/9046unix-remount.log"
uuid_of() { awk -v m="$1" '$2==m && $1 ~ /^UUID=/ {sub(/^UUID=/,"",$1); print $1}' /etc/fstab; }
for a in "${ARCHIVES[@]}"; do
    mp="/mnt/$a"
    uuid=$(uuid_of "$mp")
    [ -z "$uuid" ] && continue
    [ -e "/dev/disk/by-uuid/$uuid" ] || continue          # drive absent: nothing to do yet
    dev_now=$(readlink -f "/dev/disk/by-uuid/$uuid")
    need=""
    if ! mountpoint -q "$mp"; then
        need="not mounted"
    elif [ "$(findmnt -no SOURCE "$mp")" != "$dev_now" ]; then
        need="mounted from old device $(findmnt -no SOURCE "$mp"), drive is now $dev_now"
    elif ! timeout 20 stat "$mp/$MARKER" >/dev/null 2>&1 && \
         ! timeout 20 ls "$mp" >/dev/null 2>&1; then
        need="mount is dead (I/O errors)"
    fi
    [ -z "$need" ] && continue

    {
        echo "$(date '+%F %T') $a: $need"
        mountpoint -q "$mp" && umount -l "$mp" && echo "  lazy-unmounted stale $mp"
        fsck_out=$(timeout 3600 e2fsck -p "$dev_now" 2>&1); fsck_rc=$?
        echo "  e2fsck -p $dev_now -> rc=$fsck_rc ${fsck_out:+($(echo "$fsck_out" | tail -2 | tr '\n' ' '))}"
        if [ "$fsck_rc" -ge 4 ]; then
            echo "  NOT mounting: fsck needs a manual run (sudo e2fsck -f $dev_now)"
        elif mount "$mp" 2>&1; then
            if [ -f "$mp/$MARKER" ]; then echo "  mounted OK, marker present"
            else echo "  mounted, but MARKER MISSING (wrong drive?)"; fi
        else
            echo "  mount $mp FAILED"
        fi
    } >> "$REMOUNT_LOG" 2>&1
    ALERT_BODY+="=== ARCHIVE AUTO-REMOUNT: ${a} ===\nReason: ${need}\n$(tail -4 "$REMOUNT_LOG")\n\n"
done

# --- Check 1: iowait ---
IOWAIT=$(iostat -c 1 6 2>/dev/null | awk '
    /^[ \t]+[0-9]/ { n++; if (n > 1) { sum += $4; count++ } }
    END { if (count > 0) printf "%.1f", sum/count; else print "0" }
')
IOWAIT_TRIGGERED=$(awk -v i="$IOWAIT" -v t="$IOWAIT_THRESHOLD" 'BEGIN{print (i+0 > t+0) ? 1 : 0}')

# --- Check 2: D-state processes ---
DSTATE_PROCS=$(ps -eo pid,stat,comm,args --no-headers | awk '$2 ~ /^D/')
DSTATE_TRIGGERED=0
[ -n "$DSTATE_PROCS" ] && DSTATE_TRIGGERED=1

# --- Check 3: disk usage (real filesystems only) ---
DISK_OVER=$(df -h -x tmpfs -x devtmpfs -x squashfs -x efivarfs | awk -v t="$DISK_THRESHOLD" \
    'NR>1 { p=$5; gsub(/%/,"",p); if (p+0 > t+0) print $0 }')
DISK_TRIGGERED=0
[ -n "$DISK_OVER" ] && DISK_TRIGGERED=1

# --- Check 4: archive mounts present, marked, and read-write ---
declare -A MOUNT_TRIGGERED MOUNT_DETAIL
for a in "${ARCHIVES[@]}"; do
    mp="/mnt/$a"
    MOUNT_TRIGGERED[$a]=0
    u=$(uuid_of "$mp")
    if [ -n "$u" ] && [ ! -e "/dev/disk/by-uuid/$u" ]; then
        MOUNT_TRIGGERED[$a]=1; MOUNT_DETAIL[$a]="$mp: drive is NOT PRESENT on USB (power cut, brick unplugged, or cable). It will be remounted automatically when it reappears."
    elif ! mountpoint -q "$mp"; then
        MOUNT_TRIGGERED[$a]=1; MOUNT_DETAIL[$a]="$mp is NOT MOUNTED (drive gone from USB, or failed fsck/mount at boot)"
    elif ! timeout 20 test -f "$mp/$MARKER"; then
        MOUNT_TRIGGERED[$a]=1; MOUNT_DETAIL[$a]="$mp is mounted but $MARKER is missing (wrong drive mounted here?)"
    elif findmnt -no OPTIONS "$mp" | tr ',' '\n' | grep -qx ro; then
        MOUNT_TRIGGERED[$a]=1; MOUNT_DETAIL[$a]="$mp is mounted READ-ONLY (ext4 remounts ro after errors)"
    fi
done

# --- Check 5: ext4 error counters on the archive filesystems ---
# /sys/fs/ext4/<dev>/errors_count is persistent (stored in the superblock), so once
# nonzero it stays nonzero until fsck clears it. The alert repeats every 30 min
# until then, which is intended: errors on a backup drive need a look.
EXT4ERR_TEXT=""
for a in "${ARCHIVES[@]}"; do
    dev=$(findmnt -no SOURCE "/mnt/$a" 2>/dev/null)
    [ -z "$dev" ] && continue
    n=$(cat "/sys/fs/ext4/$(basename "$dev")/errors_count" 2>/dev/null || echo 0)
    [ "${n:-0}" -gt 0 ] && EXT4ERR_TEXT+="  /mnt/$a ($dev): errors_count=$n\n"
done
EXT4ERR_TRIGGERED=0
[ -n "$EXT4ERR_TEXT" ] && EXT4ERR_TRIGGERED=1

# --- Check 6: kernel disk I/O errors since the last run (reported once, no state) ---
KERNEL_IO=$(journalctl -k --since "@$LAST_RUN" --no-pager -q 2>/dev/null | grep -iE \
    'I/O error|blk_update_request|Buffer I/O|critical medium error|EXT4-fs (error|warning)|uas_eh_|USB disconnect|reset (high|super)-speed USB' \
    | tail -20)

# --- Check 7: AC power / battery ---
AC=$(cat "$AC_ONLINE_FILE" 2>/dev/null || echo 1)
BAT=$(cat "$BAT_CAP_FILE" 2>/dev/null || echo 100)
ONBATTERY_TRIGGERED=0
[ "$AC" = "0" ] && ONBATTERY_TRIGGERED=1
[ "$AC" = "1" ] && SHUTDOWN_SENT=0

# --- Helpers ---
check_condition() {
    local triggered=$1 last_alert=$2 was_active=$3
    if [ "$triggered" -eq 1 ]; then
        if [ "$was_active" -eq 0 ] || [ $(( NOW - last_alert )) -ge $ALERT_INTERVAL ]; then
            echo "alert"; else echo "suppress"; fi
    elif [ "$was_active" -eq 1 ]; then echo "clear"
    else echo "ok"; fi
}
check_condition_streak() {
    local triggered=$1 last_alert=$2 was_active=$3 streak=$4 threshold=$5
    if [ "$triggered" -eq 1 ]; then
        streak=$(( streak + 1 ))
        if [ "$streak" -ge "$threshold" ]; then
            if [ "$was_active" -eq 0 ] || [ $(( NOW - last_alert )) -ge $ALERT_INTERVAL ]; then
                echo "alert $streak"; else echo "suppress $streak"; fi
        else echo "wait $streak"; fi
    elif [ "$was_active" -eq 1 ]; then echo "clear 0"
    else echo "ok 0"; fi
}

# --- Evaluate ---
case "$(check_condition $IOWAIT_TRIGGERED $IOWAIT_LAST_ALERT $IOWAIT_ACTIVE)" in
    alert)    IOWAIT_LAST_ALERT=$NOW; IOWAIT_ACTIVE=1
              ALERT_BODY+="=== HIGH IOWAIT ===\n5-second average: ${IOWAIT}%  (threshold: ${IOWAIT_THRESHOLD}%)\n\n" ;;
    clear)    IOWAIT_ACTIVE=0; CLEAR_BODY+="  - iowait returned to normal\n" ;;
    suppress) IOWAIT_ACTIVE=1 ;;
    ok)       IOWAIT_ACTIVE=0 ;;
esac

read verdict new_streak <<< "$(check_condition_streak $DSTATE_TRIGGERED $DSTATE_LAST_ALERT $DSTATE_ACTIVE $DSTATE_STREAK $DSTATE_FAIL_THRESHOLD)"
DSTATE_STREAK=$new_streak
case "$verdict" in
    alert)    DSTATE_LAST_ALERT=$NOW; DSTATE_ACTIVE=1
              ALERT_BODY+="=== D-STATE PROCESSES ===\nPresent for ${new_streak} consecutive checks (~$((new_streak * 5)) min).\n$(echo "$DSTATE_PROCS" | head -10)\n\n" ;;
    clear)    DSTATE_ACTIVE=0; CLEAR_BODY+="  - D-state processes cleared\n" ;;
    suppress) DSTATE_ACTIVE=1 ;;
    wait|ok)  DSTATE_ACTIVE=0 ;;
esac

case "$(check_condition $DISK_TRIGGERED $DISK_LAST_ALERT $DISK_ACTIVE)" in
    alert)    DISK_LAST_ALERT=$NOW; DISK_ACTIVE=1
              ALERT_BODY+="=== DISK USAGE ABOVE ${DISK_THRESHOLD}% ===\n${DISK_OVER}\n\n" ;;
    clear)    DISK_ACTIVE=0; CLEAR_BODY+="  - disk usage returned to normal\n" ;;
    suppress) DISK_ACTIVE=1 ;;
    ok)       DISK_ACTIVE=0 ;;
esac

for a in "${ARCHIVES[@]}"; do
    last=$(eval echo \$MOUNT_${a}_LAST_ALERT); active=$(eval echo \$MOUNT_${a}_ACTIVE)
    case "$(check_condition ${MOUNT_TRIGGERED[$a]} $last $active)" in
        alert)    eval "MOUNT_${a}_LAST_ALERT=$NOW; MOUNT_${a}_ACTIVE=1"
                  ALERT_BODY+="=== ARCHIVE PROBLEM: ${a} ===\n${MOUNT_DETAIL[$a]}\n\n" ;;
        clear)    eval "MOUNT_${a}_ACTIVE=0"; CLEAR_BODY+="  - /mnt/${a} mounted, marked and read-write again\n" ;;
        suppress) eval "MOUNT_${a}_ACTIVE=1" ;;
        ok)       eval "MOUNT_${a}_ACTIVE=0" ;;
    esac
done

case "$(check_condition $EXT4ERR_TRIGGERED $EXT4ERR_LAST_ALERT $EXT4ERR_ACTIVE)" in
    alert)    EXT4ERR_LAST_ALERT=$NOW; EXT4ERR_ACTIVE=1
              ALERT_BODY+="=== EXT4 ERRORS RECORDED ON ARCHIVE FILESYSTEM ===\n${EXT4ERR_TEXT}\n" ;;
    clear)    EXT4ERR_ACTIVE=0; CLEAR_BODY+="  - ext4 error counters are back to 0\n" ;;
    suppress) EXT4ERR_ACTIVE=1 ;;
    ok)       EXT4ERR_ACTIVE=0 ;;
esac

if [ -n "$KERNEL_IO" ]; then
    ALERT_BODY+="=== KERNEL DISK / USB ERRORS (since $(date -d "@$LAST_RUN" '+%H:%M')) ===\n"
    ALERT_BODY+="Current device map: $(for a in "${ARCHIVES[@]}"; do printf '%s=%s ' "$a" "$(findmnt -no SOURCE /mnt/$a 2>/dev/null || echo none)"; done)\n"
    ALERT_BODY+="${KERNEL_IO}\n\n"
fi

case "$(check_condition $ONBATTERY_TRIGGERED $ONBATTERY_LAST_ALERT $ONBATTERY_ACTIVE)" in
    alert)    ONBATTERY_LAST_ALERT=$NOW; ONBATTERY_ACTIVE=1
              ALERT_BODY+="=== ON BATTERY (AC power lost) ===\nBattery at ${BAT}%. Will shut down at ${BAT_SHUTDOWN_PCT}%.\n"
              ALERT_BODY+="The archive drives have their own power bricks: unless those are on a UPS,\nthey went down with the power.\n\n" ;;
    clear)    ONBATTERY_ACTIVE=0; CLEAR_BODY+="  - AC power restored (battery ${BAT}%)\n" ;;
    suppress) ONBATTERY_ACTIVE=1 ;;
    ok)       ONBATTERY_ACTIVE=0 ;;
esac

DO_SHUTDOWN=0
if [ "$AC" = "0" ] && [ "$BAT" -le "$BAT_SHUTDOWN_PCT" ] && [ "$SHUTDOWN_SENT" -eq 0 ]; then
    DO_SHUTDOWN=1; SHUTDOWN_SENT=1
    ALERT_BODY+="=== LOW BATTERY: SHUTTING DOWN ===\nOn battery at ${BAT}% (<= ${BAT_SHUTDOWN_PCT}%). Powering off in 1 minute.\n\n"
fi

FOOTER="------------------------------------------------------------------------
WHAT THESE ALERTS MEAN AND WHAT TO DO
------------------------------------------------------------------------
ARCHIVE PROBLEM: a drive is unmounted, has no ${MARKER} marker, or went
read-only. Backup jobs must not write to it until fixed.
  1. lsblk -o NAME,SIZE,MODEL,MOUNTPOINT   -- is the drive on the USB bus?
  2. sudo dmesg | tail -40                 -- USB resets / I/O errors
  3. sudo mount -a ; findmnt /mnt/<name>
  4. If read-only: unmount, sudo e2fsck -f /dev/sdX, remount
  Drive map: 00p=W4J0GB8C 01p=W4J1X92J (ASMedia dock, SMART via smartd)
             02s=W4J1XARP (Seagate Expansion, NO SMART)

EXT4 ERRORS: the filesystem recorded errors in its superblock. They stay
recorded until an fsck: unmount, sudo e2fsck -f /dev/sdX, remount.

KERNEL DISK / USB ERRORS: reported once per occurrence. A single USB
reset can be harmless; repeated I/O errors on the same device mean a
failing drive or cable/enclosure. For 02s this is the only early warning.

ON BATTERY: wall power is gone. The box shuts itself down at ${BAT_SHUTDOWN_PCT}%.

HIGH IOWAIT / D-STATE: usually a slow or hung USB drive.
  iostat -x 1 5 ; ps -eo pid,stat,comm,args | awk '\$2~/^D/'
------------------------------------------------------------------------"

# --- Save state ---
{
    for k in IOWAIT_LAST_ALERT IOWAIT_ACTIVE DSTATE_LAST_ALERT DSTATE_ACTIVE DSTATE_STREAK \
             DISK_LAST_ALERT DISK_ACTIVE EXT4ERR_LAST_ALERT EXT4ERR_ACTIVE \
             ONBATTERY_LAST_ALERT ONBATTERY_ACTIVE SHUTDOWN_SENT; do
        echo "$k=${!k}"
    done
    for a in "${ARCHIVES[@]}"; do
        echo "MOUNT_${a}_LAST_ALERT=$(eval echo \$MOUNT_${a}_LAST_ALERT)"
        echo "MOUNT_${a}_ACTIVE=$(eval echo \$MOUNT_${a}_ACTIVE)"
    done
    echo "LAST_RUN=$NOW"
} > "$STATE_FILE"

# --- Send mail ---
if [ -n "$ALERT_BODY" ]; then
    {
        echo "To: $TO"
        echo "Subject: [${HOST}] HEALTH ALERT -- $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo -e "$ALERT_BODY"
        echo "$FOOTER"
    } | msmtp "$TO"
fi
if [ -n "$CLEAR_BODY" ]; then
    {
        echo "To: $TO"
        echo "Subject: [${HOST}] ALL CLEAR -- $(date '+%Y-%m-%d %H:%M')"
        echo ""
        echo "The following conditions have resolved:"
        echo ""
        echo -e "$CLEAR_BODY"
    } | msmtp "$TO"
fi

if [ "$DO_SHUTDOWN" -eq 1 ]; then
    sync
    shutdown -h +1 "9046unix: battery ${BAT}% on battery power, shutting down"
fi
