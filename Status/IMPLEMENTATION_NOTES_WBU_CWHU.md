IMPLEMENTATION NOTES — WorkBenchUnix + ChatWorkhorseUnix Fleet Integration
Created: 2026-06-28 UTC

========================================================================
OVERVIEW
========================================================================

Added two bare-metal Ubuntu 24.04 machines to the FLEET_OPS monitoring
system: WorkBenchUnix (WBU, bare metal) and ChatWorkhorseUnix (CWHU,
Ubuntu VM on ChatWorkhorse). Both run Immich as their primary service.

Architecture: WBU and CWHU do NOT run the full checker.py poller.
They only write heartbeat JSON files locally and rsync them to
AmsterdamDesktop's OneDrive-synced folder. Amsterdam's existing
Windows checker does all fleet polling.

========================================================================
MACHINES ADDED
========================================================================

WorkBenchUnix
  Tailscale name:  workbenchunix
  Tailscale IP:    100.105.10.123
  Primary service: Immich (port 2283)
  Probe port:      22

ChatWorkhorseUnix
  Tailscale name:  chatworkhorseunix
  Tailscale IP:    100.118.51.113
  Primary service: Immich (port 2283)
  Probe port:      22

========================================================================
NEW FILES
========================================================================

heartbeat_writer_linux.py
  One-shot Python script (cron-driven via run_heartbeat.sh).
  Collects CPU, RAM, disk, OS info, and Immich photo/video counts.
  Writes three files per run:
    heartbeat_{host}.txt         — timestamp only
    machine_info_{host}.json     — full metrics snapshot
    metrics_history_{host}.json  — rolling 120-entry history (NDJSON)
  Key implementation notes:
  - Uses /proc/meminfo, /proc/stat, df -k, /proc/uptime (no psutil)
  - Immich stats via GET /api/server/statistics with x-api-key header
  - Uses Tailscale hostname (not localhost) for Immich API calls —
    Docker on CWHU does not reliably respond on localhost after restart
  - Args: --host <tailscale-name> --output-dir <path> --immich-api-key <key>

run_heartbeat.sh
  Bash wrapper called by cron. Parameterized: run_heartbeat.sh <hostname>
  - Writes to /home/dhm/fleet_monitor/${HOST}/
  - rsyncs to drden@amsterdamdesktop:/cygdwin/d/OneDrive/_sync_monitor/${HOST}/
  - SSH key: /home/dhm/.ssh/id_ed25519_amsterdamdesktop
  - Uses rsync -a only (NOT -az — rsync 3.2.x / 3.4.x compression mismatch)
  - Immich API key hardcoded (same key works on both machines)

checkers/immich_checker.py
  Amsterdam-side checker module called by engine.py for each fleet poll.
  - GET /api/server/ping (no auth) for liveness
  - GET /api/server/version (x-api-key) for version string (e.g. v2.7.5)
  - Returns standard {status, response_time_ms, detail} dict

========================================================================
MODIFIED FILES
========================================================================

config.py
  - Added IMMICH_CONFIG dict with API keys for wbu and cwhu
  - Added WorkBenchUnix and ChatWorkhorseUnix to FLEET list
  - Fixed ChatWorkhorse IP (was 100.124.162.73, correct is 100.110.253.46)

engine.py
  - Added immich_checker to import line
  - Added "immich": immich_checker to CHECKER_MAP

websites/Backup/ST/tiles.html  (live copy: D:\OneDrive\_sync_monitor\Web\ST\tiles.html)
  - renderPrimaryMetric(svc) -> renderPrimaryMetric(svc, machine)
  - Added Immich case: shows UP/DOWN + photo/video counts from machine_info
  - renderModalService(svc) -> renderModalService(svc, machine)
  - Added Immich case: shows VERSION, PHOTOS, VIDEOS in detail panel
  - Updated both .map(renderModalService) call sites to pass machine

========================================================================
CRON SETUP (both machines, user dhm)
========================================================================

*/2 * * * * /home/dhm/repos/scripts/Status/run_heartbeat.sh <hostname> >> /home/dhm/fleet_monitor/heartbeat.log 2>&1

========================================================================
RSYNC / SSH NOTES
========================================================================

- Passwordless SSH key auth to Amsterdam Windows OpenSSH server
- Admin key path on Windows: C:\ProgramData\ssh\administrators_authorized_keys
- Cygwin path for rsync dest: /cygdrive/d/OneDrive/_sync_monitor/
- rsync -z flag omitted: CWHU has rsync 3.2.7, Amsterdam has 3.4.1;
  zstd compression negotiation fails between these versions

========================================================================
IMMICH API NOTES
========================================================================

- /api/server/ping       — no auth required (liveness check)
- /api/server/version    — requires x-api-key (version string)
- /api/server/statistics — requires x-api-key (photo/video counts)
- Both WBU and CWHU use the same Immich API key (same Immich account)
- Docker on CWHU: use Tailscale hostname for API calls, not localhost
  (localhost hangs after container restart; 0.0.0.0:2283 binding is
  present but unreliable for loopback on this VM configuration)
- Immich image tag is :v2 (floating) — containers may restart on
  Watchtower updates. API keys persist in Postgres across restarts
  so this is not currently a problem, but pinning to a specific
  version (e.g. :v2.7.5) is recommended for stability.

========================================================================
PENDING / FUTURE
========================================================================

- Last backup timestamp: WBU -> /mnt/backup-c last write time
  (deferred until backup automation is stable)
- Last sync timestamp: WBU -> Mac Mini last sync completed
  (deferred until sync automation is stable)
- Consider pinning Immich Docker image to specific version tag
  to prevent unexpected Watchtower-triggered restarts
