# launchagents — auto-started local servers (macOS)

Repo-versioned launchd LaunchAgents for the personal HTTP servers that used
to be started by hand after every reboot. `install.sh` copies each plist
into `~/Library/LaunchAgents` and loads it; from then on the servers start
at every login, restart automatically if they crash, and log to files.

## Agents

| Label | What it runs | Port | Log |
|---|---|---|---|
| `com.dennis.search-adv-web` | search_adv web GUI (`search_adv/.venv` python, `search_adv_web.py`) | 5025 | `~/Library/Logs/search_adv_web.log` |
| `com.dennis.search-shows-web` | search_shows web GUI — cast/actor/show-info via TVmaze/TMDB/OMDb (`search_shows/.venv` python, `search_shows_web.py`) | 5020 | `~/Library/Logs/search_shows_web.log` |
| `com.dennis.travel-http` | `python3 -m http.server` in `~/repos/dennyrgood.github.io/travel` | 5030 | `~/Library/Logs/travel_http.log` |
| `com.dennis.comfy-fleet-http` | `python3 -m http.server` (bound `0.0.0.0` — LAN + Tailscale, not public internet) in `comfy-reports/fleet-output` — ComfyUI fleet reports/explorer | 5050 | `~/Library/Logs/comfy_fleet_http.log` |
| `com.dennis.comfy-fleet-scan` | `comfyui/scheduled_scan.sh` — daily 5am: SSH-scans ImageBeast/ChatWorkhorse/TravelBeast, refreshes `fleet_report_latest.html`/`fleet_explorer_latest.html`, prunes old runs (keep last 3) | — | `~/Library/Logs/comfy_fleet_scan.log` |
| `com.dennis.tmdb-explorer` | TMDB explorer web GUI — raw TMDB lookup/browse (`tmdb_explorer/.venv` python, `tmdb_explorer.py`). Runs on both mb (the canonical/live instance at `mb.ldmathes.cc:5035`) and mmm (independent second instance, added 2026-08-11) — different hosts, same plist and port, no conflict. | 5035 | `~/Library/Logs/tmdb_explorer.log` |
| `com.dennis.heartbeat-writer` | `Status/onedrive_heartbeat_writer_all_macs.py` (fleet heartbeat → local `~/fleet_monitor`) | — | `~/Library/Logs/heartbeat_writer.log` |
| `com.dennis.fleet-metrics-server` | `Status/fleet_metrics_server.py` (serves `~/fleet_monitor` to the checker over Tailscale) | 9100 | `~/Library/Logs/fleet_metrics_server.log` |
| `com.dennis.mmm-plex-backup` | `MathesMacMini/backup_plex_to_fleetnas.sh` — daily 4am rsync mirror, Mac Mini Plex library → FleetNAS | — | `~/Library/Logs/mmm_plex_backup.log` (script's own detailed log: `~/.cache/fleetnas-sync/plex_*.log`) |
| `com.dennis.mmm-nightly-summary` | `MathesMacMini/nightly_summary.sh` — daily 7am email report on the Plex backup's health | — | `~/Library/Logs/mmm_nightly_summary.log` |
| `com.dennis.mmm-health-monitor` | `MathesMacMini/mathes-mac-mini-health-monitor.sh` — every 5 min, Plex/Syncthing process+API health + disk usage, alert/all-clear emails | — | `~/Library/Logs/mmm_health_monitor.log` |
| `com.dennis.money-web` | money web app (`~/repos/money`: `.venv/bin/money serve`, waitress on 127.0.0.1 only; tailnet via `tailscale serve`). mb for now (warm standby), FleetDev later. Added 2026-10-15. | 5040 | `~/Library/Logs/money_web.log` |
| `com.dennis.money-backup` | `money backup` — daily 02:30, snapshots every money book into `~/MoneyData/backups` (30 daily, 12 monthly), integrity-checked; local only for now | — | `~/Library/Logs/money_backup.log` |
| `com.dennis.money-copy-off` | `money copy-off` — daily 03:00, mb only: backs up the money books, then rsyncs `~/MoneyData` over SSH to FleetDev (`~/MoneyData` there, served by FleetDev's read-only standby; `[copy.*]` in money's config.toml), never deleting there; each snapshot hash-checked on arrival. Added 2026-10-19. | — | `~/Library/Logs/money_copy_off.log` |
| `com.dennis.money-copy-to-nas` | `FleetDev/money-copy-to-nas.sh` — daily 06:30, FleetDev only: pushes `~/MoneyData` to FleetNAS (`misc/money/MoneyData`), never deleting there; each book's newest snapshot hash-checked; warns if mb's copy is over 2 days old. Installed by install.sh on FleetDev (its `fleetdev` case, 2026-10-20 19:24 UTC). Added 2026-10-19. | — | `~/Library/Logs/money_copy_to_nas.log` |
| `com.dennis.money-take-copies` | `money take-copies` — daily 06:00 and at load, on the money **standby** only (FleetDev until cutover, then mb): puts the newest snapshot of each book sent by the primary's copy-off into the books folder, hash- and integrity-checked, for the read-only app (`standby = true`). Refuses on a primary. Installed by install.sh on FleetDev (its `fleetdev` case, 2026-10-20 19:24 UTC). Added 2026-10-20. | — | `~/Library/Logs/money_take_copies.log` |
| `com.dennis.notes-to-self` | `FleetDev/notes_to_self_to_email.py` (`/usr/bin/python3`) — every 60s, FleetDev only: emails each iMessage you text yourself to dennyrgood@yahoo.com via msmtp (account `icloud`). Reads only the notes-to-self chat in `~/Library/Messages/chat.db`; last handled ROWID in `~/.local/state/notes-to-self.state` (first run starts at the newest message, no backlog). Needs **Full Disk Access for `/usr/bin/python3`** (already granted for heartbeat-writer). Skips the `s3g is back online` alerts wbu sends into the same thread. Added 2026-10-24. | — | `~/Library/Logs/notes_to_self.log` |

Port notes: 5000 is taken by macOS AirPlay; travel deliberately sits at 5030
so the 8xxx range stays free for ad-hoc testing (the generic `start_http`
script at the repo root is unchanged for that).

To set up another Mac (heartbeat only, incl. the required Full Disk Access
grant), see `MIGRATION.md`.

## Install / update / remove

`install.sh` is host-aware — it looks at `scutil --get ComputerName` and
only installs the agents that machine should run: mb (`denniss-macbook-air`,
primary) gets its GUIs, the fleet agents, `tmdb-explorer` and the money agents, but not
the `mmm-*` agents or `comfy-fleet-scan` (changed 2026-10-15 06:21 UTC; before that it got everything); mb2 (`denniss-2nd-macbook-air`) is fleet-only
(`heartbeat-writer` + `fleet-metrics-server` — no Ollama, no
search_adv/search_shows/travel/tmdb GUIs); mmm (`mathes-mac-mini`) gets
those two plus its own three Plex/Syncthing agents (`mmm-plex-backup`,
`mmm-nightly-summary`, `mmm-health-monitor`) plus `tmdb-explorer` (added
2026-08-11 — a second, independent instance for browsing directly on that
box). FleetDev (`fleetdev`) gets what is loaded there: the GUIs, `comfy-fleet-http`/`-scan`,
the fleet agents, `tmdb-explorer`, its own health monitor and nightly summary, `fleet-digest`
and the money agents; its `wall-*` agents are installed by hand (their plists aren't in this
folder). Since 2026-10-21 09:59 UTC, mb's list also has its health monitor, nightly summary and
`fleet-digest`, and `--all` means every plist in this folder. An unrecognized host aborts with an error rather than silently
installing everything; add it to the `case` statement in `install.sh` first.

`mmm-plex-backup` briefly lived as a crontab entry instead (2026-08-05) while a
launchd-specific rsync timeout was being chased down — see the script's own header
for the full investigation. Root cause turned out to be an unanswered TCC "Removable
Volumes" consent dialog (cron hit it too, just hadn't been caught in testing yet), not
launchd itself — fixed by granting it, moved back to launchd for consistency.

```bash
cd ~/repos/scripts/launchagents
./install.sh              # install or reload this host's agents (safe to re-run)
./install.sh --uninstall  # stop and remove this host's agents
./install.sh --all        # force every agent regardless of host (debugging only)
```

Re-run `./install.sh` after editing a plist — it boots out the old copy
first. Adding a new server = drop another `.plist` in this dir, add its
label to the right host's list in `install.sh`, and re-run.

## Day-to-day

```bash
# restart after a code change (replaces the old Ctrl-C / rerun cycle)
launchctl kickstart -k gui/$UID/com.dennis.search-shows-web

# stop until next login / reinstall
launchctl bootout gui/$UID/com.dennis.search-shows-web

# is it running?  (columns: PID, last-exit-status, label — 0 = last exit was clean)
launchctl list | grep com.dennis

# full detail: state, last run, next scheduled, plist path
launchctl print gui/$UID/com.dennis.search-shows-web

# watch a log
tail -f ~/Library/Logs/search_shows_web.log
```

(`$UID` is a zsh/bash builtin that expands to the current user's uid —
works unmodified on any Mac; `$(id -u)` is the fully portable spelling if
`$UID` isn't set in your shell.)

Note on the exit-status column: `launchctl kickstart -k` restarts a service
by sending it SIGTERM, so right after using `-k` the status column will show
`-15` (i.e. "killed") even though the restart succeeded — that's expected,
not a fault. It clears on the *next* natural exit. If you want a clean `0`
immediately (e.g. before double-checking health), bootout + bootstrap instead
of kickstart:

```bash
launchctl bootout gui/$UID/com.dennis.search-shows-web
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.dennis.search-shows-web.plist
```

## Ollama (not an agent here)

The tray Ollama.app is the only Ollama server on this Mac. It binds
127.0.0.1; tailnet access is provided by a persistent Tailscale forward
(`tailscale serve --bg --tcp 11434 tcp://127.0.0.1:11434`, disable with
`tailscale serve --tcp=11434 off`). **Never `export OLLAMA_HOST` in shell
init files** — the tray app captures the shell environment and its server
will try to bind that address (a remote host's IP = permanent crash loop,
the 2026-07-16 "hosed install" that wasn't). Point the CLI at a remote
server with an alias instead (see `~/.zshrc`).

## Caveats

- The plists hardcode `/Users/dennishmathes` paths — Mac-specific. The
  Ubuntu equivalent would be systemd user units, not covered here.
- `KeepAlive` means a server that dies at startup (e.g. port already in
  use by a manually-started copy) will be retried in a loop — check the
  log and kill the manual copy rather than fighting launchd.
