#!/usr/bin/python3
# verify-restic-integrity-scheduled.py -- unattended integrity check of the
# off-site Immich restic repo held on this machine (mgc / MacMiniGC).
# Created: 2026-10-23 12:30 UTC. macOS port of Surface3GC/verify-restic-integrity-scheduled.ps1.
#
# NO PASSPHRASE REQUIRED (unchanged from the .ps1): every restic object --
# packs, indexes, snapshots, keys -- is named by the SHA-256 of its own bytes,
# so integrity = re-hash and compare to the filename. No key on this box; a
# stolen mini or drive yields nothing. Logical consistency is still verified
# nightly on wbu (restic check --read-data); Syncthing keeps both sides identical.
#
# DIFFERENCES FROM THE .ps1
#   - Full check every run (bucket "all"), not 1/12 per month. The slice existed
#     because the Surface Pro 3 took hours over ~85 GiB; an M1 on a 7200 RPM
#     drive should take roughly 10-15 min (estimate, not measured).
#   - Requires the volume to be MOUNTED (os.path.ismount), not merely present:
#     an unmounted /Volumes/X can be an empty directory.
#   - Files that vanish mid-scan (Syncthing applying wbu's monthly prune) are
#     skipped, not counted as unreadable.
#   - Fails if zero objects were checked -- catches an empty/unsynced repo and
#     a macOS privacy (TCC) block on the external drive, which os.walk would
#     otherwise swallow silently.
#   - JSON written atomically (.tmp + rename); fleet_metrics_server's allowlist
#     won't serve the .tmp, so wbu never fetches half a file.
#
# Read by wbu's syncthing_offsite_status.sh via GC_VERIFY_URL; it parses
# ok, mismatches, unreadable, files_checked, bucket, finished_utc.

import hashlib, json, os, socket, sys, time
from datetime import datetime, timezone
from pathlib import Path

VOLUME   = Path("/Volumes/GC_Media")
REPO     = VOLUME / "immich-restic"
OUT_DIR  = Path.home() / "fleet_monitor"   # served by fleet_metrics_server.py on :9100
OUT_FILE = OUT_DIR / "watchdog_restic-offsite_macminigc.json"
SUBDIRS  = ("data", "index", "snapshots", "keys")   # not the root: .stfolder/.stignore live there
MAX_BAD_LISTED = 25   # fetched over HTTP nightly; a failing drive could produce thousands
CHUNK = 1024 * 1024
HEX = set("0123456789abcdef")


def utc(ts):
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_result(ok, note, started, checked=0, mismatch=0, unreadable=0, bad=()):
    finished = time.time()
    r = {
        "check": "restic-offsite-integrity",
        "host": socket.gethostname(),
        "repo": str(REPO),
        "ok": ok,
        "note": note,
        "bucket": "all",
        "files_checked": checked,
        "mismatches": mismatch,
        "unreadable": unreadable,
        "bad_files": list(bad),
        "started_utc": utc(started),
        "finished_utc": utc(finished),
        "elapsed_sec": int(finished - started),
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = OUT_FILE.with_name(OUT_FILE.name + ".tmp")
    tmp.write_text(json.dumps(r, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, OUT_FILE)
    print(json.dumps(r, indent=2))


def main():
    started = time.time()
    checked = mismatch = unreadable = 0
    bad = []

    def note_bad(entry):
        if len(bad) < MAX_BAD_LISTED:
            bad.append(entry)

    def walk_error(err):
        nonlocal unreadable
        unreadable += 1
        note_bad(f"UNREADABLE DIR {err.filename}")

    if not os.path.ismount(VOLUME):
        write_result(False, f"{VOLUME} is not mounted", started)
        return 1
    # config is the one file NOT named by its content hash; its absence means
    # wrong path, or the immich-restic folder hasn't been synced here yet.
    if not (REPO / "config").is_file():
        write_result(False, f"no restic config at {REPO} -- wrong path or not synced?", started)
        return 1

    for sub in SUBDIRS:
        d = REPO / sub
        if not d.is_dir():
            continue
        for root, _dirs, files in os.walk(d, onerror=walk_error):
            for name in files:
                if len(name) != 64 or not set(name) <= HEX:
                    continue   # not a restic object (e.g. a Syncthing .tmp)
                h = hashlib.sha256()
                try:
                    with open(os.path.join(root, name), "rb") as f:
                        for chunk in iter(lambda: f.read(CHUNK), b""):
                            h.update(chunk)
                except FileNotFoundError:
                    continue   # removed mid-scan by a synced prune
                except OSError:
                    unreadable += 1
                    note_bad(f"UNREADABLE {name}")
                    continue
                checked += 1
                if h.hexdigest() != name:
                    mismatch += 1
                    note_bad(name)

    if checked == 0:
        write_result(False, "0 restic objects checked -- repo empty, unsynced, or access blocked",
                     started, checked, mismatch, unreadable, bad)
        return 1
    if mismatch or unreadable:
        write_result(False, f"{mismatch} corrupt, {unreadable} unreadable of {checked} checked",
                     started, checked, mismatch, unreadable, bad)
        return 1
    write_result(True, f"{checked} files verified, all hashes match",
                 started, checked, mismatch, unreadable, bad)
    return 0


if __name__ == "__main__":
    _started = time.time()
    try:
        sys.exit(main())
    except Exception as e:   # mirror the .ps1: any crash still publishes a failed result
        write_result(False, f"check failed: {e}", _started)
        sys.exit(1)
