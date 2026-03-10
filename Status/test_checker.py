"""
test_checker.py — Fleet Checker Diagnostic Test Script
Run from the fleet_checker directory on Amsterdam before deploying.
Tests path resolution, file writing, and each checker module individually.

Usage:
    python test_checker.py              # all tests
    python test_checker.py --no-network # skip all network tests
    python test_checker.py --machine imagebeast  # test one machine only
"""

import sys
import json
import argparse
import traceback
from pathlib import Path
from datetime import datetime, timezone

# Ensure imports resolve from this directory
sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    STATUS_DIR, CHECKER_HOST, FLEET,
    TIMEOUT_TCP_MS, TIMEOUT_HTTP_MS, TIMEOUT_PUBLIC_MS,
)
from checkers import tcp_checker, http_checker
from checkers import ollama_checker, comfyui_checker, openwebui_checker, flask_checker, plex_checker
from reporters import json_reporter

PASS = "  [PASS]"
FAIL = "  [FAIL]"
SKIP = "  [SKIP]"
INFO = "  [INFO]"

results = []


def record(label, passed, detail=""):
    results.append((label, passed, detail))
    icon = PASS if passed else FAIL
    print(f"{icon} {label}" + (f" — {detail}" if detail else ""))


# ---------------------------------------------------------------------------
# 1. Config & path checks
# ---------------------------------------------------------------------------

def test_paths():
    print("\n── Path & Config ─────────────────────────────────────────")

    record("STATUS_DIR resolves", True, str(STATUS_DIR))
    record("CHECKER_HOST set", bool(CHECKER_HOST), CHECKER_HOST)
    record("FLEET has machines", len(FLEET) > 0, f"{len(FLEET)} machines defined")

    # OneDrive parent exists
    onedrive_parent = STATUS_DIR.parent
    record("OneDrive parent exists", onedrive_parent.exists(), str(onedrive_parent))


def test_write():
    print("\n── File Write ────────────────────────────────────────────")

    try:
        STATUS_DIR.mkdir(parents=True, exist_ok=True)
        record("STATUS_DIR created/exists", True, str(STATUS_DIR))
    except Exception as e:
        record("STATUS_DIR mkdir", False, str(e))
        return

    # Write test
    test_file = STATUS_DIR / "test_write.tmp"
    try:
        test_file.write_text("fleet checker test", encoding="utf-8")
        record("Write test file", True, str(test_file))
    except Exception as e:
        record("Write test file", False, str(e))
        return

    # Read back
    try:
        content = test_file.read_text(encoding="utf-8")
        record("Read back test file", content == "fleet checker test", content)
    except Exception as e:
        record("Read back test file", False, str(e))

    # Cleanup
    try:
        test_file.unlink()
        record("Cleanup test file", True)
    except Exception as e:
        record("Cleanup test file", False, str(e))


# ---------------------------------------------------------------------------
# 2. Reporter dry run
# ---------------------------------------------------------------------------

def test_reporter():
    print("\n── JSON Reporter (dry run) ───────────────────────────────")

    fake_state = {
        "meta": {
            "timestamp_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "checker_host": CHECKER_HOST,
            "poll_interval_seconds": 30,
            "fleet_version": "1.0",
            "cycle_duration_ms": 0,
        },
        "summary": {
            "machines_total": 1, "machines_up": 1, "machines_down": 0, "machines_unknown": 0,
            "services_total": 1, "services_up": 1, "services_down": 0, "services_unknown": 0,
            "public_endpoints_total": 0, "public_endpoints_up": 0, "public_endpoints_down": 0,
        },
        "machines": [
            {
                "machine": {
                    "display_name": "TestMachine",
                    "tailscale_name": "testmachine",
                    "tailscale_ip": "100.0.0.1",
                    "primary_role": "Test",
                },
                "poll": {"timestamp_utc": "2026-01-01T00:00:00Z", "poll_duration_ms": 0, "checker_host": CHECKER_HOST},
                "host": {"status": "up", "response_time_ms": 1, "detail": None},
                "services": [],
            }
        ],
    }

    try:
        json_reporter.report(fake_state, STATUS_DIR, CHECKER_HOST)
        master = STATUS_DIR / "server_status_all.json"
        per_machine = STATUS_DIR / "server_status_testmachine.json"
        log_file = STATUS_DIR / f"checker_{CHECKER_HOST}.log"
        record("Master JSON written", master.exists(), str(master))
        record("Per-machine JSON written", per_machine.exists(), str(per_machine))
        record("Log file written", log_file.exists(), str(log_file))

        # Validate master JSON is parseable
        data = json.loads(master.read_text(encoding="utf-8"))
        record("Master JSON parses correctly", "meta" in data and "machines" in data)

        # Cleanup test artifacts
        for f in [per_machine]:
            try:
                f.unlink(missing_ok=True)
            except Exception:
                pass

    except Exception as e:
        record("Reporter dry run", False, traceback.format_exc())


# ---------------------------------------------------------------------------
# 3. Network checks — TCP host reachability
# ---------------------------------------------------------------------------

def test_tcp(machines):
    print("\n── Layer 1: TCP Host Reachability ────────────────────────")
    for m in machines:
        name = m["tailscale_name"]
        display = m["display_name"]
        try:
            probe_port = m.get("probe_port", 80)
            probe_host = "127.0.0.1" if name == CHECKER_HOST else name
            result = tcp_checker.check(probe_host, TIMEOUT_TCP_MS, port=probe_port)
            status = result["status"]
            ms = result["response_time_ms"]
            detail = result.get("detail") or ""
            label = f"TCP {display} ({name})"
            record(label, status == "up", f"{status} {ms}ms {detail}".strip())
        except Exception as e:
            record(f"TCP {display}", False, str(e))


# ---------------------------------------------------------------------------
# 4. Network checks — Layer 2 service health per machine
# ---------------------------------------------------------------------------

def test_services(machines):
    print("\n── Layer 2: Tailscale Service Checks ─────────────────────")

    checker_map = {
        "ollama": ollama_checker,
        "comfyui": comfyui_checker,
        "openwebui": openwebui_checker,
        "flask": flask_checker,
        "plex": plex_checker,
    }

    for m in machines:
        name = m["tailscale_name"]
        display = m["display_name"]

        # First confirm host is reachable
        probe_port = m.get("probe_port", 80)
        probe_host = "127.0.0.1" if name == CHECKER_HOST else name
        host = tcp_checker.check(probe_host, TIMEOUT_TCP_MS, port=probe_port)

        if host["status"] != "up":
            print(f"\n  {display} — host unreachable, skipping service checks")
            continue

        print(f"\n  {display}:")
        for svc in m.get("services", []):
            label = f"    {svc['name']} :{svc['port']} [{svc['check_type']}]"
            check_type = svc["check_type"]

            if check_type == "tcp":
                result = tcp_checker.check(name, TIMEOUT_TCP_MS, port=svc["port"])
            else:
                mod = checker_map.get(check_type)
                if mod is None:
                    record(label, False, f"unknown check_type: {check_type}")
                    continue
                try:
                    result = mod.check(name, svc["port"], TIMEOUT_HTTP_MS)
                except Exception as e:
                    record(label, False, traceback.format_exc())
                    continue

            passed = result["status"] == "up"
            detail = f"{result['status']} {result['response_time_ms']}ms"
            if result.get("detail"):
                detail += f" — {result['detail']}"
            record(label, passed, detail)


# ---------------------------------------------------------------------------
# 5. Network checks — Layer 3 public endpoints
# ---------------------------------------------------------------------------

def test_public(machines):
    print("\n── Layer 3: Public Endpoint Checks ───────────────────────")

    found_any = False
    for m in machines:
        for svc in m.get("services", []):
            url = svc.get("public_url")
            if not url:
                continue
            found_any = True
            label = f"{m['display_name']} / {svc['name']} → {url}"
            try:
                result = http_checker.get(url, TIMEOUT_PUBLIC_MS)
                passed = result["status"] == "up"
                detail = f"HTTP {result['http_code']} {result['response_time_ms']}ms"
                if result.get("detail"):
                    detail += f" — {result['detail']}"
                record(label, passed, detail)
            except Exception as e:
                record(label, False, str(e))

    if not found_any:
        print(f"{SKIP} No public_url entries in selected machines")


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

def print_summary():
    print("\n── Summary ───────────────────────────────────────────────")
    passed = sum(1 for _, p, _ in results if p)
    failed = sum(1 for _, p, _ in results if not p)
    total = len(results)
    print(f"  {passed}/{total} passed", end="")
    if failed:
        print(f"  ({failed} FAILED)")
        print("\n  Failed tests:")
        for label, p, detail in results:
            if not p:
                print(f"    {FAIL} {label}" + (f" — {detail}" if detail else ""))
    else:
        print(" — all clear")
    print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fleet Checker diagnostic tests")
    parser.add_argument("--no-network", action="store_true", help="Skip all network tests")
    parser.add_argument("--machine", type=str, default=None,
                        help="Test one machine only (tailscale_name, e.g. imagebeast)")
    args = parser.parse_args()

    print(f"Fleet Checker — Diagnostic Test")
    print(f"Checker host : {CHECKER_HOST}")
    print(f"Status dir   : {STATUS_DIR}")
    print(f"Timestamp    : {datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')}")

    # Filter fleet if --machine specified
    machines = FLEET
    if args.machine:
        machines = [m for m in FLEET if m["tailscale_name"] == args.machine]
        if not machines:
            print(f"\nERROR: No machine named '{args.machine}' in config.")
            print("Available:", ", ".join(m["tailscale_name"] for m in FLEET))
            sys.exit(1)
        print(f"Filtering to: {machines[0]['display_name']}")

    # Always run these
    test_paths()
    test_write()
    test_reporter()

    # Network tests
    if args.no_network:
        print(f"\n{SKIP} Network tests skipped (--no-network)")
    else:
        test_tcp(machines)
        test_services(machines)
        test_public(machines)

    print_summary()
