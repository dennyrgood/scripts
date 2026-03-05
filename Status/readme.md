# Fleet Status Checker System

This repository contains scripts and configurations for monitoring a distributed fleet of services across multiple hosts using dual redundant instances of the Fleet Status Checker. Each instance operates independently, providing continuous health checks even if one node fails.

## Overview

The system consists of three main components:

1. **Checker**: A Python script (`checker.py`) that monitors service health on remote hosts
2. **Fleet API**: A Flask server (`fleet_api.py`) that serves status JSON data
3. **Dashboards**: Static HTML pages displaying the status data in user-friendly formats

### Redundant Architecture

The system runs two independent instances on separate Windows 11 machines:

| Instance | Machine Name    | OneDrive Sync Folder                        | API Endpoint                              | Dashboard                               |
|----------|-----------------|---------------------------------------------|-------------------------------------------|-----------------------------------------|
| **#1**   | AmsterdamDesktop | `_sync_monitor/amsterdamdesktop/`          | `https://fleet.ldmathes.cc/api/status`    | [status.ldmathes.cc](https://status.ldmathes.cc) |
| **#2**   | ChatWorkhorse   | `_sync_monitor/chatworkhorse/`             | `https://chatworkhou.se.fleetldmathes.cc/api/status` (backup) | [Backup Dashboard](https://fleet.ldmathes.cc/status-bkp/) |

Each instance independently polls and monitors all fleet machines, writing its own status file. This ensures:
- ✅ **Data redundancy**: Continuous monitoring even if one instance goes offline
- ✅ **UI diversity**: Two different dashboard views (desktop vs mobile-optimized)

### Monitored Fleet

The system monitors 6 hosts across different locations:

| Display Name        | Hostname                  | Primary Role     | Tailscale IP    | Services                          |
|---------------------|---------------------------|------------------|-----------------|-----------------------------------|
| ImageBeast          | `imagebeast`              | ComfyUI Primary  | 100.107.247.38  | ComfyUI, Ollama                   |
| ChatWorkhorse       | `chatworkhorse`           | Ollama Primary   | 100.124.162.73  | ComfyUI, Ollama, OpenWebUI        |
| TravelBeast         | `travelbeast`             | Mobile/Travel    | 100.73.82.42    | ComfyUI, Ollama (no public URLs)  |
| Amsterdam           | `amsterdamdesktop`        | Flask/API Primary| 100.125.37.114  | Ollama, Flask APIs, OpenWebUI, Fleet API, ComfyUI |
| MacBook Air Prime   | `denniss-macbook-air`     | Ollama Backup    | 100.72.187.19   | Ollama                            |
| MacBook Air 2       | `denniss-2nd-macbook-air` | Ollama Backup    | 100.84.152.110  | Ollama                            |

## Architecture Diagram

```
┌───────────────═══════════════════════════════════════╗
│                    DUAL REDUNDANT INSTANCES                 │
├─────────────══════════════╗═══════════╗═════════════════╝
│   Amsterdam Instance     │    ChatWorkhorse Instance       │
├─────────────══════════════║═══════════╗═══════════════════╝
│  checker.py              │    checker.py                       │
│    ↓ writes               │          ↓ writes                   │
│  server_status_all.json  │   server_status_all.json       │
│  via OneDrive sync        │      via OneDrive sync            │
│                          │                                     │
│ localhost:5010          │     localhost:5010                │
│  (fleet_api.py)          │      (fleet_api.py)               │
│    ↓ serves               │           ↓ serves                  │
│ https://fleet.ldmathes.cc/api/status │ https://backup.fleetldmathes.cc/api/status │
│                          │                                     │
│ Dashboard:             │   Dashboard:                      │
│  status.ldmathes.cc     │   backup-dash.fleetldmathes.cc  │
│  (desktop-optimized)    │      (mobile-optimized: sm/)       │
└─────────────══════════════║═══════════╗═══════════════════╝
                              ‖‖
                              ‖‖ (Both monitor via Tailscale)
                              \/
              ┌──────────══════════════╗════════════════════╗
              │          MONITORED HOSTS          │
              ├─════════════╗════════╗═╗════════╗═╗═══════╝
              │  imagebeast   chatworkhorse        │
              │  travelbeast amsterdamdesktop      │
              │  macbook-air-1 macbook-air-2       │
              └──────────══════════════╗════════════════════╝
```

## Technical Architecture

### Three-Layer Monitoring Cascade

The system uses a tiered check approach for every service:

#### **Layer 1 — Host Reachability (Tailscale TCP)**

Runs before any other checks:

```python
# Runs before any other checks
probe_host = "127.0.0.1" if machine == checker_host else TAILSCALE_NAME
host_result = tcp_checker.check(host, timeout_ms=3000)
if host_result["status"] != "up":
    return UNKNOWN for all services on this machine  # SKIP remaining layers
```

- Uses `probe_port` from config (typically 8188 or 11434)
- **Critical:** If host unreachable, Layers 2 & 3 are skipped entirely for efficiency

#### **Layer 2 — Tailscale Service Health**

After host confirmed up, each service gets checked via specialized modules:

- `ollama_checker`: Checks `/api/tags` AND `/api/ps`
- `comfyui_checker`: Checks `/system_stats` and `/queue`
- `openwebui_checker`: Checks `/health`
- `flask_checker`: GET `/` (accepts HTTP 4xx as OK)

#### **Layer 3 — Public Endpoint Check**

If `public_url` is configured in config, runs after Layer 2:

```python
pub_raw = http_checker.get(public_url, timeout_ms=3000)
if http_code == 302: detail = "Zero Trust redirect"
elif http_code == 401: detail = "Zero Trust auth required"
elif http_code >= 400: fail with reason
# Otherwise: success if HTTP response received
```

- Handles Cloudflare/AWS Zero Trust middlewares correctly
- Accepts any HTTP response (including 4xx) as service alive unless it's a 5xx or connection failure

## Detailed Components

### 1. Checker Module Design

**Note:** The actual entry point and orchestrator is `engine.py`, which handles the three-layer monitoring cascade (host → service → public endpoints).

**Module Interface:** Each checker module implements `check(host, port, timeout_ms)` → returns `{status, response_time_ms, detail}`

### Checker Modules Overview

| Module           | HTTP Endpoints Checked      | Logic                                        |
|------------------|-----------------------------|-----------------------------------------------|
| `ollama_checker.py`    | `/api/tags`, `/api/ps`       | Requires both endpoints responding            |
| `comfyui_checker.py`   | `/system_stats`, `/queue`    | Monitors GPU load, queue length, system health|
| `openwebui_checker.py`| `/health`                   | Any HTTP 2xx = OK                             |
| `flask_checker.py`     | `/`                         | Accepts HTTP 4xx as alive (only 5xx fail)     |
| `http_checker.py`      | Variable                    | Generic GET request with validation           | |

**Key Behavioral Notes:**
- Flask services treat HTTP 400/401/404 responses as "service alive" (just not ideal)
- Ollama requires both `/api/tags` and `/api/ps` to succeed for overall UP status
- ComfyUI monitors queue depth; if stuck in processing, health degrades
- Runs automatically via Windows Task Scheduler on each instance machine
- Logs to both console and rotating file in status directory

**Configuration File**: `config.py` (shared across instances)
- Defines all monitored machines and their services
- Contains polling intervals, timeouts, and public URLs for health checks

**Output Location**:
```bash
_OnDrive_\_sync_monitor/<hostname>/server_status_all.json
```
Where `<hostname>` is the machine running the checker:
- `amsterdamdesktop` → writes to OneDrive `_sync_monitor/amsterdamdesktop/`
- `chatworkhorse` → writes to OneDrive `_sync_monitor/chatworkhorse/`

### 2. Fleet API (`fleet_api.py`)

**Functionality**: Exposes health check data via a RESTful JSON API.

**Server Details**:
- Runs on port 5010 (configurable)
- Binds to `0.0.0.0` (accessible from any network interface)
- Serves data from the local `server_status_all.json` file
- Includes custom CORS headers for cross-origin requests

**Endpoints**:
| Endpoint         | Description                            | Returns                                                                 |
|------------------|----------------------------------------|-------------------------------------------------------------------------|
| `GET /api/status`| Full fleet status data                 | Complete JSON with all machines, services, summary stats                |
| `GET /health`      | Health check endpoint                  | `{"status": "ok", "checker_host": "...", "timestamp": "..."}`           | |

**HTTP Headers Added**:
- `X-Checker-Host`: Name of the machine running this checker instance
- `X-Data-Age`: Seconds since last status update
- `Access-Control-Allow-Origin: *`: Enables CORS for dashboard access

### 3. Dashboards

#### Main Dashboard (`websites/status/`)
- **URL**: [https://status.ldmathes.cc](https://status.ldmathes.cc)
- **Source Data**: Amsterdam instance API
- **Features**: Desktop-optimized, detailed machine cards, full service details
- **Style**: Modern dark theme with Tailwind CSS, JetBrains Mono font
- **Data Freshness Detection**: Shows "DATA STALE" banner if no data for >90 seconds since last poll cycle
- **Secondary Machine Styling**: MacBook Airs styled lighter on main dashboard to distinguish from primary infrastructure

#### Backup Dashboard (`websites/status-bkp/`)
- **URL**: [https://fleet.ldmathes.cc/status-bkp/](https://fleet.ldmathes.cc/status-bkp/)
- **Source Data**: ChatWorkhorse instance API (backup feed)
- **Features**: Mobile-first design, collapsible machine cards, simplified view
- **Style**: Tailwind CSS + JetBrains Mono font, optimized for quick status checks
- **Auto-Fallback**: Automatic link detection to itself if main dashboard is stale

## Setup and Configuration

### Prerequisites
- **Python 3.8+** on both monitoring machines
- **OneDrive sync client** running on both machines
- **Tailscale** installed and configured to connect all fleet machines
- **Flask** for the API server (install: `pip install flask`)

### Common Steps for Both Instances

1. **Clone Repository**
   ```bash
   git clone https://github.com/your-repo/fleet-monitor.git
   cd fleet-monitor
   pip install flask
   ```

2. **Configure Environment Variables** (in `config.py`, lines 8-9):
   ```python
   CHECKER_HOST = os.environ.get("FLEET_CHECKER_HOST") or os.environ.get("COMPUTERNAME", "unknown").lower()
   
   ONEDRIVE_PATH = Path(
       os.environ.get("OneDriveConsumer")
       or os.environ.get("OneDrive")
       or Path.home() / "OneDrive"
   )
   ```
   
   **Environment variables used**:
   - `FLEET_CHECKER_HOST`: Override for CHECKER_HOST (optional)
   - `COMPUTERNAME`: Windows native hostname (auto-detected if not set)
   - `OneDrive` / `OneDriveConsumer`: OneDrive sync folder path

3. **Configure Fleet Definition** (`config.py`, lines 28-215):
   - Edit the `FLEET` list to add/remove monitored machines
   - Each machine entry includes: display name, Tailscale details, probe port, and services
   - Define public URLs for external service health checks (set to `null` if internal only)

4. **Set Up Windows Task Scheduler** on each monitoring machine:
   ```
   Trigger (Trigger): Daily, Startup, or Specific Time (每日，启动时，或特定时间)
   Action (Action): Run program (运行程序)
     Program/script: python.exe (程序/脚本)
         Add arguments: checker.py (添加参数)
        Start at: C:\Path\To\fleet-monitor (起始于)
   ```

5. **Start Flask API Server**:
   ```bash
   python fleet_api.py
   ```
   
   Expected output:
   ```
   Starting Fleet API for amsterdamdesktop...
   Serving data from: C:\Users\...\OneDrive\_sync_monitor\amsterdamdesktop\server_status_all.json
    * Running on http://0.0.0.0:5010
   ```

6. **Configure Reverse Proxy** (for public access):
   - Map `https://fleet.ldmathes.cc` to `http://<amsterdam-ip>:5010`
   - Map `https://status.ldmathes.cc` and `/status-bkp/` to static HTML files
   - Same for ChatWorkhorse backup instance

### Instance-Specific Details

#### Amsterdam PC (Primary)
```bash
# Computer Name: amsterdamdesktop
# OneDrive Folder: _sync_monitor/amsterdamdesktop/server_status_all.json
# Public URLs exposed via reverse proxy:
#   https://fleet.ldmathes.cc/api/status    → fleet_api.py endpoint
#   https://status.ldmathes.cc              → status/index.html dashboard
```

#### ChatWorkhorse PC (Backup)
```bash
# Computer Name: chatworkhorse
# OneDrive Folder: _sync_monitor/chatworkhorse/server_status_all.json
# Public URLs exposed via reverse proxy:
#   https://backup.fleetldmathes.cc/api/status  → fleet_api.py endpoint
#   https://fleet.ldmathes.cc/status-bkp/       → sm/index.html dashboard
```

## Data Flow

```
[Amsterdam Desktop]                [ChatWorkhorse]
      │                                  │
      ▼                                  ▼
checker.py (runs every 30s)     checker.py (runs every 30s)
      │                                  │
      ▼ write status                    ▼ write status
Onedrive sync \_sync_monitor/      Onedrive sync \_sync_monitor/
    │                   │                  │                   │
    ├── amsterdamdesktop/              ├── chatworkhorse/       
    │   └── server_status_all.json     │   └── server_status_all.json
    │                                  │
    ▼ serve API (port 5010)            ▼ serve API (port 5010)
    fleet.ldmathes.cc/api/status       backup.fleetldmathes.cc/api/status
           │                                  │
           ▼                                  ▼
  status.ldmathes.cc              fleet.ldmathes.cc/status-bkp/
  (status/index.html)                   (sm/index.html)
```

## Monitoring Configuration

Polling and timeout settings in `config.py`:

| Setting                      | Default | Description                                                      |
|------------------------------|---------|------------------------------------------------------------------|
| `POLL_INTERVAL_SECONDS`      | 30      | Time between full monitoring cycles                              |
| `TIMEOUT_TCP_MS`             | 3000    | Layer 1 host reachability check (Tailscale)                      |
| `TIMEOUT_HTTP_MS`            | 1500    | Layer 2 service checks (Ollama, ComfyUI, etc.)                   |
| `TIMEOUT_PUBLIC_MS`          | 3000    | Layer 3 public endpoint checks                                    | |

## Service Types Monitored

### Monitorable Service Types & Check Modules

The checker supports multiple service types via dedicated modules in `checkers/`:

| Type        | Module                     | Endpoint(s)                         | Success Criteria                              |
|-------------|----------------------------|-------------------------------------|-----------------------------------------------|
| **TCP**       | `tcp_checker.py`           | Port check only                     | Port responding (Layer 1 host reachability)   |
| **HTTP**      | `http_checker.py`          | Configured public_url               | HTTP response (no 5xx/connect failure)        |
| **Ollama**    | `ollama_checker.py`        | `/api/tags`, `/api/ps`              | Both endpoints respond successfully           |
| **ComfyUI**   | `comfyui_checker.py`       | `/system_stats`, `/queue`           | System stats + queue info successful          |
| **OpenWebUI** | `openwebui_checker.py`     | `/health`                           | Health endpoint returns HTTP 2xx              |
| **Flask**     | `flask_checker.py`         | `/`                                 | Any HTTP response (4xx acceptable)            |

**All service checks log**: response times, detailed status messages, and error specifics.

### Configuration: Service Priority Labels

Services are assigned priority labels that appear on dashboards:

| Label    | Meaning                                        | Example                                 |
|----------|------------------------------------------------|-----------------------------------------|
| **P**      | Primary (critical)                             | Fleet API, OpenWebUI chat, Image generation |
| **B2**     | Beta Tier 2                                    | Secondary image services                |
| **B5**     | Beta Tier 5                                    | Mobile/travel devices                   |
| **B9**     | Beta Tier 9                                    | Amsterdam Flask/ComfyUI backup roles    |
| **B99**    | Beta Tier 99 (backup/offline-capable)          | MacBook Air Ollama instances            |

These tags help operators quickly identify critical vs. auxiliary services.

### Configuration: Probe Ports

The `probe_port` defined for each machine is used **only for Layer 1 TCP reachability** checks:
- Typically 8188 (ComfyUI) or 11434 (Ollama)
- Port 22 (SSH) is NOT used — most machines are Windows without SSH
- If host probe fails, all services on that machine mark as UNKNOWN

## Troubleshooting

### Checker Not Running
- Verify Task Scheduler is configured correctly
- Check OneDrive sync folder for `checker_<hostname>_app.log`
- Ensure Python path is correctly set in Task Scheduler

### API Returns 503 Error
- Verify Flask server is running (`python fleet_api.py`)
- Confirm port 5010 is accessible from your network
- Check that `server_status_all.json` exists in OneDrive sync folder

### Dashboard Shows "Link_Lost"
- Verify CORS headers are set (should be `*` in `fleet_api.py`)
- Ensure reverse proxy is forwarding to correct Flask endpoint
- Check browser console for fetch errors

### Tailscale Connections Failing
- Confirm all machines are on the same Tailscale network
- Verify firewall allows traffic on service ports (8188, 11434, 5000, etc.)
- Check `probe_port` configuration in `config.py` matches accessible ports

## Contributing and Development

To contribute to this system:

1. **Fork the repository** and clone your fork locally
2. **Create an issue** for any bugs found or features proposed
3. **Submit pull requests** with clear descriptions of changes
4. **Test on a single machine** before deploying across instances

### Development Checklist
- [ ] Update `config.py` if adding/removing monitored machines
- [ ] Test checker functionality locally (`python checker.py`)
- [ ] Verify Flask API responds correctly (`curl http://localhost:5010/api/status`)
- [ ] Confirm dashboard displays data (check browser console for errors)

## Version Notes

- **Current Architecture**: Dual redundant instances monitoring 6 hosts via Tailscale
- **OneDrive Sync**: Critical for status file synchronization between checker and API
- **Port Usage**: Fleet API runs on port 5010 (not 5000 - Flask services use different ports)
- **Dashboard Strategy**: One desktop-optimized, one mobile-first backup version

---

**This README.md provides a comprehensive overview of the dual-instance Fleet Status Checker system. The redundancy architecture ensures continuous monitoring availability even during individual node failures. For deployment-specific configurations, adjust `config.py` and reverse proxy settings accordingly.**