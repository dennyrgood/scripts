"""
config.py — Fleet Checker Configuration
All machines, services, ports, check types, and public endpoints defined here.
No code changes needed to add/remove machines or services — edit this file only.
"""

import os
from pathlib import Path

# ---------------------------------------------------------------------------
# OneDrive / output paths
# ---------------------------------------------------------------------------

# Which machine is running this checker instance
CHECKER_HOST = os.environ.get("FLEET_CHECKER_HOST") or os.environ.get("COMPUTERNAME", "unknown").lower()

ONEDRIVE_PATH = Path(
    os.environ.get("OneDriveConsumer")
    or os.environ.get("OneDrive")
    or Path.home() / "OneDrive"
)

STATUS_DIR = ONEDRIVE_PATH / "_sync_monitor" / CHECKER_HOST
MASTER_STATUS_FILE = STATUS_DIR / "server_status_all.json"



# ---------------------------------------------------------------------------
# Polling / timeout settings
# ---------------------------------------------------------------------------

POLL_INTERVAL_SECONDS = 30
TIMEOUT_TCP_MS = 3000         # Layer 1 host reachability
TIMEOUT_HTTP_MS = 1500        # Layer 2 Tailscale service checks
TIMEOUT_PUBLIC_MS = 3000      # Layer 3 public endpoint checks

# ---------------------------------------------------------------------------
# Fleet definition
# ---------------------------------------------------------------------------
# check_types controls which checker modules run for each service:
#   "tcp"       — TCP connect only (no HTTP)
#   "ollama"    — Ollama API (/api/tags + /api/ps)
#   "comfyui"   — ComfyUI API (/system_stats + /queue)
#   "openwebui" — OpenWebUI health (/health)
#   "flask"     — Flask alive (GET /)
#
# probe_port: port used for Layer 1 TCP host reachability check.
#             Pick the most reliably open port on that machine.
#             Port 22 (SSH) is NOT used — most machines are Windows without SSH.
#
# public_url: present = Layer 3 check runs; null = Tailscale only

FLEET = [
    {
        "display_name": "ImageBeast",
        "tailscale_name": "imagebeast",
        "tailscale_ip": "100.107.247.38",
        "primary_role": "ComfyUI Primary",
        "probe_port": 8188,
        "services": [
            {
                "name": "ComfyUI",
                "port": 8188,
                "priority": "P",
                "check_type": "comfyui",
                "public_url": "https://image.ldmathes.cc",
            },
            {
                "name": "Ollama",
                "port": 11434,
                "priority": "B2",
                "check_type": "ollama",
                "public_url": None,
            },    
        ],
    },
    {
        "display_name": "ChatWorkhorse",
        "tailscale_name": "chatworkhorse",
        "tailscale_ip": "100.124.162.73",
        "primary_role": "Ollama Primary",
        "probe_port": 11434,
        "services": [
            {
                "name": "Ollama",
                "port": 11434,
                "priority": "P",
                "check_type": "ollama",
                "public_url": None,
            },
            {
                "name": "OpenWebUI",
                "port": 8080,
                "priority": "P",
                "check_type": "openwebui",
                "public_url": "https://talk.ldmathes.cc",
            },
            {
                "name": "ComfyUI",
                "port": 8188,
                "priority": "B2",
                "check_type": "comfyui",
                "public_url": "https://clips.ldmathes.cc",
            },
            {
                "name": "Fleet API",
                "port": 5010,
                "priority": "P",
                "check_type": "flask",
                "public_url": "https://fleet-bkp.ldmathes.cc",
            },
        ],
    },
    {
        "display_name": "TravelBeast",
        "tailscale_name": "travelbeast",
        "tailscale_ip": "100.73.82.42",
        "primary_role": "Mobile/Travel",
        "probe_port": 8188,
        "services": [
            {
                "name": "ComfyUI",
                "port": 8188,
                "priority": "B5",
                "check_type": "comfyui",
                "public_url": None,
            },
            {
                "name": "Ollama",
                "port": 11434,
                "priority": "B5",
                "check_type": "ollama",
                "public_url": None,
            },
        ],
    },
    {
        "display_name": "Amsterdam",
        "tailscale_name": "amsterdamdesktop",
        "tailscale_ip": "100.125.37.114",
        "primary_role": "Flask / OpenWebUI Primary",
        "probe_port": 5000,
        "services": [
            {
                "name": "OpenWebUI",
                "port": 8080,
                "priority": "P",
                "check_type": "openwebui",
                "public_url": "https://chat.ldmathes.cc",
            },
            {
                "name": "Flask/API",
                "port": 5000,
                "priority": "P",
                "check_type": "flask",
                "public_url": "https://api.ldmathes.cc",
            },
            {
                "name": "Flask/API-Edit",
                "port": 5001,
                "priority": "P",
                "check_type": "flask",
                "public_url": "https://api-edit.ldmathes.cc",
            },
            {
                "name": "Flask/Weather",
                "port": 5005,
                "priority": "P",
                "check_type": "flask",
                "public_url": "https://weatherproxy.ldmathes.cc",
            },
            {
                "name": "Ollama",
                "port": 11434,
                "priority": "B9",
                "check_type": "ollama",
                "public_url": None,
            },
            {
                "name": "Fleet API",
                "port": 5010,
                "priority": "P",
                "check_type": "flask",
                "public_url": "https://fleet.ldmathes.cc",
            },
        ],
    },
    {
        "display_name": "MacBook Air Prime",
        "tailscale_name": "denniss-macbook-air",
        "tailscale_ip": "100.72.187.19",
        "primary_role": "Ollama B99",
        "probe_port": 11434,
        "services": [
            {
                "name": "Ollama",
                "port": 11434,
                "priority": "B99",
                "check_type": "ollama",
                "public_url": None,
            },
        ],
    },
    {
        "display_name": "MacBook Air 2",
        "tailscale_name": "denniss-2nd-macbook-air",
        "tailscale_ip": "100.84.152.110",
        "primary_role": "Ollama B99",
        "probe_port": 11434,
        "services": [
            {
                "name": "Ollama",
                "port": 11434,
                "priority": "B99",
                "check_type": "ollama",
                "public_url": None,
            },
        ],
    },
]
