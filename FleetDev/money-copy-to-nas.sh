#!/bin/bash
# Created: 2026-10-19 04:48 UTC — pushes FleetDev's copy of mb's money data folder (~/MoneyData, sent each
# night by mb's `money copy-off`) to FleetNAS's misc share, then checks the newest snapshot of each book there by
# SHA-256 against FleetDev's. Runs ON FleetDev, daily, via launchagents/com.dennis.money-copy-to-nas.plist, until
# money moves to FleetDev (money PLAN M9). mb doesn't push to the NAS itself: away from home its link (ship, Tailscale
# relay) is too slow and drops; FleetDev sits on the NAS's LAN.
#
# Shape follows WorkBenchUnix/backup_immich_db_to_fleetnas.sh and MathesMacMini/backup_plex_to_fleetnas.sh: a key
# for the NAS only, ConnectTimeout/ServerAlive on every ssh/rsync, UGOS's share-name path for rsync and the real path
# for ssh. Differences: never --delete (a file lost upstream never removes the good one on the NAS), and a half-sent
# file waits in .rsync-partial for the next run instead of starting over.
# 2026-10-20 18:53 UTC — ~/MoneyData-from-mb -> ~/MoneyData on FleetDev, misc/money/MoneyData-from-mb -> misc/money/MoneyData on the
#   NAS: FleetDev's standby serves the copy as it is (money README "FleetDev as the standby"). Snapshots are now
#   read from FleetDev's own backup folder, the one mb's copy fills.
# 2026-10-20 19:54 UTC — the live books (app/*.db and their -wal/-shm) and the Sunriise jars are left out, as mb's copy-off does:
#   after cutover FleetDev's books are written while this runs, and the checked snapshots in backups/ are their safe
#   copies; the jars are downloaded by money's install-tools.sh.
set -euo pipefail

SRC="$HOME/MoneyData"
DEST_HOST="dhm@192.168.178.123"
SSH_KEY="$HOME/.ssh/id_ed25519_fleetnas"
SSH_OPTS="ssh -i $SSH_KEY -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3"
DEST_RSYNC="$DEST_HOST:misc/money/MoneyData/"            # UGOS's rsync: share name, no /volume1
DEST_PATH="/volume1/misc/money/MoneyData"                 # plain ssh commands: the real path
STALE_DAYS=2                                              # warn when mb's newest snapshot is older than this
RSYNC="rsync"
[ -x /opt/homebrew/bin/rsync ] && RSYNC=/opt/homebrew/bin/rsync

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1"; }

log "=== money copy: FleetDev ~/MoneyData -> FleetNAS misc/money/MoneyData ==="
if [ ! -d "$SRC/backups/daily" ]; then
    log "FAIL nothing to send: no $SRC/backups/daily (has mb's money copy-off reached FleetDev yet?)"
    exit 1
fi
if ! $SSH_OPTS -n "$DEST_HOST" "mkdir -p '$DEST_PATH'"; then
    log "FAIL can't reach $DEST_HOST over SSH without a password, or can't make $DEST_PATH"
    exit 1
fi

set +e
"$RSYNC" -rlt --itemize-changes --timeout=600 --partial-dir=.rsync-partial --exclude=.rsync-partial/ \
    --exclude='/app/*.db' --exclude='*.db-wal' --exclude='*.db-shm' --exclude='*.db-journal' --exclude='*.part' \
    --exclude='/*.jar' \
    -e "$SSH_OPTS" "$SRC/" "$DEST_RSYNC" > /tmp/money-copy-to-nas.out 2>&1
RC=$?
set -e
SENT=$(grep -cE '^[<>]f' /tmp/money-copy-to-nas.out || true)
if [ "$RC" -ne 0 ]; then
    log "FAIL rsync exited $RC: $(tail -1 /tmp/money-copy-to-nas.out)"
    exit 1
fi
log "$SENT file(s) sent"

# The newest daily snapshot of each book: FleetDev's hash must match the NAS's. (mb's copy-off already checked
# FleetDev's against mb's.) Snapshot names are <book>-YYYY-MM-DD.db, so a plain sort puts the newest last.
BAD=0
TODAY=$(date +%s)
for BOOK in $(ls "$SRC/backups/daily" | sed -nE 's/^(.+)-[0-9]{4}-[0-9]{2}-[0-9]{2}\.db$/\1/p' | sort -u); do
    NEWEST=$(ls "$SRC/backups/daily/$BOOK"-*.db | sort | tail -1)
    REL="backups/daily/$(basename "$NEWEST")"
    HERE=$(shasum -a 256 "$NEWEST" | cut -d' ' -f1)
    THERE=$($SSH_OPTS -n "$DEST_HOST" "sha256sum '$DEST_PATH/$REL'" 2>/dev/null | cut -d' ' -f1 || true)
    if [ -n "$THERE" ] && [ "$HERE" = "$THERE" ]; then
        log "checked $BOOK: $REL matches"
    else
        log "FAIL $BOOK: the NAS copy of $REL doesn't match"
        BAD=1
    fi
    DAY=$(basename "$NEWEST" .db | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}$')
    AGE=$(( (TODAY - $(date -j -f %Y-%m-%d "$DAY" +%s)) / 86400 ))
    if [ "$AGE" -gt "$STALE_DAYS" ]; then
        log "WARN $BOOK: mb's newest snapshot is from $DAY ($AGE days): mb's copy-off hasn't reached FleetDev since"
    fi
done

if [ "$BAD" -ne 0 ]; then
    exit 1
fi
log "=== done ==="
