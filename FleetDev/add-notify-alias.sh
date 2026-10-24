#!/bin/bash
# add-notify-alias.sh -- add a `notify` shell function that iMessages you via
# FleetDev's notify-me. Run once per box (wbu, fd, mb, ...). Created: 2026-10-24.
#   notify "backup done"        notify --email "also to Yahoo"
#   long-job; notify "done rc=$?"     some-cmd | notify
# On FleetDev it calls notify-me directly; elsewhere it goes over ssh.
set -u
case "$SHELL" in */zsh) RC=~/.zshrc ;; *) RC=~/.bashrc ;; esac
if grep -q '^notify()' "$RC" 2>/dev/null; then echo "already in $RC"; exit 0; fi
if [ -x ~/repos/scripts/FleetDev/notify-me ] && [ "$(hostname -s)" = FleetDev ]; then
    FN='notify() { ~/repos/scripts/FleetDev/notify-me "$@"; }'
else
    FN='notify() { local e=; [ "${1:-}" = --email ] && { e=--email; shift; }; if [ $# -gt 0 ]; then printf "%s\n" "$*"; else cat; fi | ssh -o ConnectTimeout=10 dennishmathes@fleetdev repos/scripts/FleetDev/notify-me $e; }'
fi
printf '\n# notify: iMessage yourself via FleetDev (scripts/FleetDev/add-notify-alias.sh)\n%s\n' "$FN" >> "$RC"
echo "added to $RC -- open a new shell (or: source $RC), then: notify hello"
