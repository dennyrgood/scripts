#!/usr/bin/env python3
"""
kuma_sync.py — build Uptime Kuma monitors from Status/config.py's FLEET.

Created 2026-11-14 for pi400 (spuiraspberry), which runs Uptime Kuma 2.x in Docker
on :3001 as an independent, non-Windows second opinion on the fleet. config.py stays
the single source of truth: add a host/service there, re-run this, and Kuma follows.

What it creates, per FLEET host (one Kuma *group* per host, named display_name):
  - "<host> · ping"            ICMP ping to tailscale_ip
  - "<host> · port <probe>"    TCP connect to probe_port (22 for every host today)
  - one monitor per service, mapped from check_type to the same endpoint the
    Python checker hits (ollama /api/tags, comfyui /system_stats, immich
    /api/server/ping, ...). http_heartbeat services become an HTTP check of
    http://<target>:9100/heartbeat_<target>.txt, filed under the TARGET host's
    group (so cwh's "Amsterdam Desktop Heartbeat Check" lands under Amsterdam).
    NOTE: Kuma only checks that file is served (HTTP 200), not that its
    timestamp is fresh — a hung writer is still only caught by checker.py.
  - "<svc> (public)" for every service with a public_url (any HTTP < 500 = up,
    same rule as checkers/http_checker.py, so Cloudflare redirects/403s pass).

Checks target tailscale_ip, not the MagicDNS name, because Kuma runs inside a
Docker container whose DNS may not see MagicDNS.

Alert grace mirrors config.py: PORTABLE_HOSTS get ~PORTABLE_GRACE_SECONDS of
retries before going red, REMOTE_LINK_HOSTS ~REMOTE_LINK_GRACE_SECONDS, everyone
else FAIL_STREAK_THRESHOLD consecutive failures.

Hosts whose tailscale_ip is a LAN address (FleetNAS, 192.168.178.x) are skipped
unless --include-lan: the Pi is on a different LAN (192.168.0.x) and can't reach them.

Idempotent: monitors are matched by name; existing ones are edited, missing ones
added. Nothing is ever deleted — remove stale monitors in the Kuma UI.

Usage (from anywhere; reads config.py next to this file):
    kuma_sync.py --dry-run                 # print the plan, no Kuma needed
    kuma_sync.py                           # sync to http://spuiraspberry:3001
Options: --url, --user (default dhm); password from $KUMA_PASS or prompted.
Requires: pip install uptime-kuma-api-v2  (Kuma 2.x; plain uptime-kuma-api for 1.23)
"""
import argparse
import getpass
import ipaddress
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import config  # noqa: E402

INTERVAL = 60          # seconds between checks
RETRY_INTERVAL = 60    # seconds between retries once a check fails
MANAGED_NOTE = "Managed by scripts/Status/kuma_sync.py from config.py — edits here get overwritten."

# check_type -> (path, accept-any-<500?) ; None path = plain TCP port check
HTTP_PATHS = {
    "ollama":    ("/api/tags", False),
    "comfyui":   ("/system_stats", False),
    "openwebui": ("/health", False),
    "flask":     ("/", True),                    # flask_checker: any non-5xx = alive
    "immich":    ("/api/server/ping", False),
    "plex":      ("/identity", False),           # no token needed
    "syncthing": ("/rest/noauth/health", False), # no API key needed
}
ANY_BELOW_500 = ["200-299", "300-399", "400-499"]
OK_ONLY = ["200-299"]


def retries_for(host):
    """Map config.py's grace rules onto Kuma's maxretries (retries before 'down')."""
    if host in config.PORTABLE_HOSTS:
        return max(1, config.PORTABLE_GRACE_SECONDS // RETRY_INTERVAL)
    if host in config.REMOTE_LINK_HOSTS:
        return max(1, config.REMOTE_LINK_GRACE_SECONDS // RETRY_INTERVAL)
    return max(0, config.FAIL_STREAK_THRESHOLD - 1)


def is_lan(ip):
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return addr.is_private and addr not in ipaddress.ip_network("100.64.0.0/10")


def build_plan(include_lan=False):
    """Return (groups, monitors, skipped). monitors carry a 'group' key = group name."""
    by_name = {h["tailscale_name"]: h for h in config.FLEET}
    groups, monitors, skipped = [], [], []
    seen_urls = set()

    def add(group, **m):
        m["group"] = group
        monitors.append(m)

    for h in config.FLEET:
        host, ip, dn = h["tailscale_name"], h["tailscale_ip"], h["display_name"]
        if is_lan(ip) and not include_lan:
            skipped.append(f"{dn} ({ip}) — LAN-only, not reachable from pi400")
            continue
        r = retries_for(host)
        groups.append(dn)
        add(dn, type="ping", name=f"{dn} · ping", hostname=ip, maxretries=r)
        add(dn, type="port", name=f"{dn} · port {h['probe_port']}",
            hostname=ip, port=h["probe_port"], maxretries=r)

        for s in h.get("services", []):
            ct, port, sname = s["check_type"], s.get("port", 0), s["name"]
            if ct == "http_heartbeat":
                target = s.get("check_params", {}).get("target_host", host)
                t = by_name.get(target)
                if t is None or (is_lan(t["tailscale_ip"]) and not include_lan):
                    continue
                url = f"http://{t['tailscale_ip']}:{config.METRICS_PORT}/heartbeat_{target}.txt"
                if url in seen_urls:
                    continue
                seen_urls.add(url)
                add(t["display_name"], type="http", name=f"{t['display_name']} · heartbeat :{config.METRICS_PORT}",
                    url=url, accepted=OK_ONLY, maxretries=retries_for(target))
            elif ct in HTTP_PATHS:
                path, lenient = HTTP_PATHS[ct]
                add(dn, type="http", name=f"{dn} · {sname} :{port}",
                    url=f"http://{ip}:{port}{path}",
                    accepted=ANY_BELOW_500 if lenient else OK_ONLY, maxretries=r)
            else:  # "tcp" and anything unknown
                add(dn, type="port", name=f"{dn} · {sname} :{port}",
                    hostname=ip, port=port, maxretries=r)

            if s.get("public_url"):
                add(dn, type="http", name=f"{dn} · {sname} (public)",
                    url=s["public_url"], accepted=ANY_BELOW_500,
                    maxretries=max(0, config.FAIL_STREAK_THRESHOLD - 1))
    return groups, monitors, skipped


def print_plan(groups, monitors, skipped):
    for g in groups:
        print(f"[{g}]")
        for m in (m for m in monitors if m["group"] == g):
            target = m.get("url") or f"{m['hostname']}" + (f":{m['port']}" if m.get("port") else "")
            print(f"  {m['type']:5} {m['name']:45} {target}  (retries {m['maxretries']})")
    for s in skipped:
        print(f"SKIPPED: {s}")
    print(f"\n{len(groups)} groups, {len(monitors)} monitors")


def sync(url, user, password, groups, monitors):
    try:  # Kuma 2.x needs the fork; the original lib only speaks 1.21-1.23
        from uptime_kuma_api_v2 import UptimeKumaApi, MonitorType
    except ImportError:
        from uptime_kuma_api import UptimeKumaApi, MonitorType

    types = {"http": MonitorType.HTTP, "port": MonitorType.PORT, "ping": MonitorType.PING}
    added = edited = 0
    with UptimeKumaApi(url) as api:
        api.login(user, password)
        existing = {m["name"]: m for m in api.get_monitors()}
        # Kuma's "Default enabled" notification flag is applied only by the web UI,
        # not the socket API — so attach the default notification(s) to anything we
        # add. Edits leave a monitor's notifications alone (edit_monitor merges).
        default_notifs = [n["id"] for n in api.get_notifications() if n.get("isDefault")]

        group_ids = {}
        for g in groups:
            if g in existing:
                group_ids[g] = existing[g]["id"]
            else:
                group_ids[g] = api.add_monitor(type=MonitorType.GROUP, name=g,
                                               description=MANAGED_NOTE,
                                               notificationIDList=default_notifs)["monitorID"]
                added += 1

        for m in monitors:
            kw = dict(type=types[m["type"]], name=m["name"], parent=group_ids[m["group"]],
                      interval=INTERVAL, retryInterval=RETRY_INTERVAL,
                      maxretries=m["maxretries"], description=MANAGED_NOTE)
            if m["type"] == "http":
                kw.update(url=m["url"], accepted_statuscodes=m["accepted"])
            else:
                kw.update(hostname=m["hostname"])
                if m["type"] == "port":
                    kw.update(port=m["port"])
            if m["name"] in existing:
                api.edit_monitor(existing[m["name"]]["id"], **kw)
                edited += 1
            else:
                api.add_monitor(notificationIDList=default_notifs, **kw)
                added += 1
    print(f"Done: {added} added, {edited} updated.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--url", default=os.environ.get("KUMA_URL", "http://spuiraspberry:3001"))
    ap.add_argument("--user", default=os.environ.get("KUMA_USER", "dhm"))
    ap.add_argument("--dry-run", action="store_true", help="print the plan only")
    ap.add_argument("--include-lan", action="store_true", help="also monitor LAN-only hosts (FleetNAS)")
    a = ap.parse_args()

    groups, monitors, skipped = build_plan(a.include_lan)
    print_plan(groups, monitors, skipped)
    if a.dry_run:
        return
    password = os.environ.get("KUMA_PASS") or getpass.getpass(f"Kuma password for {a.user}: ")
    sync(a.url, a.user, password, groups, monitors)


if __name__ == "__main__":
    main()
