#!/bin/bash
# /home/dhm/repos/scripts/9046Unix/9046unix-latency-log.sh
# 2026-11-08 — created. Does the 300 KB/s NAS copy add latency for the household
# (24x7 gamer, evening Netflix)? Root crontab, every 5 minutes.
#
# Each run pings the router and 1.1.1.1 (20 pings, 0.5 s apart, ~10 s) and appends one
# row to $LOG. A/B test: on every second run (odd 5-minute slot) the copy is PAUSED
# for the measurement (SIGSTOP on rsync + its ssh child, ~15 s), so both states get
# sampled at the same times of day even while the copy runs nearly 24 h. Costs ~2.5 %
# of copy speed. A detached safety timer sends SIGCONT after 40 s even if this script
# dies (on 2026-11-08 a hung manual test left the copy paused).
# PIDs are found by exact process name, so this script can never match itself.
#
# Row: epoch  hour  state  router_avg  router_max  inet_avg  inet_max  inet_loss%
#   state: copy   = a copy was running during the pings
#          paused = a copy was running but paused for the pings
#          idle   = no copy running at all
# The nightly summary (9046unix-nightly-summary.sh) reports the last 24 h from it.

LOG=/var/lib/9046unix/latency.tsv
mkdir -p "$(dirname "$LOG")"
GW=$(ip route show default | awk '{print $3; exit}')

R=$(pgrep -x rsync | tr '\n' ' ')
S=$(for p in $R; do pgrep -P "$p" -x ssh; done | tr '\n' ' ')
PIDS="$R $S"

STATE=idle
if [ -n "${R// /}" ]; then
    STATE=copy
    if [ $(( 10#$(date +%M) / 5 % 2 )) -eq 1 ]; then
        STATE=paused
        setsid nohup bash -c "sleep 40; kill -CONT $PIDS 2>/dev/null" >/dev/null 2>&1 < /dev/null &
        kill -STOP $PIDS 2>/dev/null
        sleep 4   # let queued copy traffic drain before measuring
    fi
fi

stats() {  # prints: avg max loss%
    ping -q -n -c 20 -i 0.5 -W 2 "$1" 2>/dev/null | awk -F'[/ ]+' '
        /packet loss/ { for (i = 1; i <= NF; i++) if ($i ~ /%$/) { loss = $i; sub(/%/, "", loss) } }
        /^rtt/        { avg = $8; max = $9 }
        END { printf "%s %s %s", (avg == "" ? "NA" : avg), (max == "" ? "NA" : max), (loss == "" ? 100 : loss) }'
}
TR=$(mktemp); TI=$(mktemp)
stats "$GW" > "$TR" &          # both at the same time, so they see the same moment
stats 1.1.1.1 > "$TI" &
wait
read -r R_AVG R_MAX _ < "$TR"
read -r I_AVG I_MAX I_LOSS < "$TI"
rm -f "$TR" "$TI"

[ "$STATE" = paused ] && kill -CONT $PIDS 2>/dev/null

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$(date +%H)" "$STATE" \
    "$R_AVG" "$R_MAX" "$I_AVG" "$I_MAX" "$I_LOSS" >> "$LOG"
