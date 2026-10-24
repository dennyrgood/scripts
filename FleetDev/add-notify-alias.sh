#!/bin/bash
# add-notify-alias.sh -- add a `notify` shell function that iMessages you via
# FleetDev's notify-me. Run once per box (wbu, fd, mb, ...). Created: 2026-10-24.
#   notify "backup done"        notify --email "also to Yahoo"
#   long-job; notify "done rc=$?"     some-cmd | notify
# On FleetDev it calls notify-me directly; elsewhere it goes over ssh.
set -u
case "$SHELL" in */zsh) RC=~/.zshrc ;; *) RC=~/.bashrc ;; esac
if [ -x ~/repos/scripts/FleetDev/notify-me ] && [ "$(hostname -s)" = FleetDev ]; then
    FN='notify() { ~/repos/scripts/FleetDev/notify-me "$@"; }'
else
    FN='notify() { local e=; case "${1:-}" in -h|--help) ssh -o ConnectTimeout=10 dennishmathes@fleetdev repos/scripts/FleetDev/notify-me --help </dev/null; return;; --email) e=--email; shift;; esac; if [ $# -gt 0 ]; then printf "%s\n" "$*"; else cat; fi | ssh -o ConnectTimeout=10 dennishmathes@fleetdev repos/scripts/FleetDev/notify-me $e; }'
fi
# Re-running replaces an older version of the function.
if grep -q '^notify()' "$RC" 2>/dev/null; then
    cp -p "$RC" "$RC.bak.notify" || exit 1
    grep -v -e '^notify()' -e '^# notify: iMessage yourself' "$RC.bak.notify" > "$RC" || { cp -p "$RC.bak.notify" "$RC"; echo "FAILED, $RC restored"; exit 1; }
fi
printf '\n# notify: iMessage yourself via FleetDev (scripts/FleetDev/add-notify-alias.sh)\n%s\n' "$FN" >> "$RC"
echo "installed in $RC -- open a new shell (or: source $RC), then: notify hello"
