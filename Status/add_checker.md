# How to Add a New Service Checker

This guide documents the process for adding new service health checkers to the Fleet Checker system. Use this template when adding support for additional services.

## Example Reference
All steps are illustrated with our Plex checker implementation as the reference example.

---

## Step 1: Create the Checker File

Create a new file at `checkers/{service_name}_checker.py` following this structure:

### Required Structure

```python
"""
checkers/{service_name}_checker.py — {Service name} health check
{Layer info - e.g., Layer 2 API check or Layer 3 public proxy check}
Returns standard service result with detail string.
"""

import time
from datetime import datetime, timezone

def check(tailscale_name: str, port: int, timeout_ms: int) -> dict:
    """
    Check {service name} on tailscale_name:port.
    
    Detail strings (passing):
        "{service_info} • {additional_details}"
    
    Detail strings (failing):
        "Connection error to {url}"
        "Connection timeout"
        "API unavailable"
        etc.
    """
    start_time = time.monotonic()

    # Get credentials/settings from config if needed
    from config import SERVICE_CONFIG  # Replace with actual config variable
    
    machine_config = SERVICE_CONFIG.get(tailscale_name)
    
    if not machine_config:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=f"No {service_name} config for {tailscale_name}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    # Extract credentials/URLs from config
    service_url = machine_config.get("service_url")
    service_token = machine_config.get("service_token")

    try:
        # Make the actual check (API call, HTTP request, etc.)
        # For example with plexapi:
        # service = PlexServer(service_url, service_token)
        
        # Check status and gather metrics
        # status = service.some_status_property
        
        # Build detail string from gathered information
        
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="up",
            response_time_ms=elapsed,
            detail=f"{friendly_name} v{version} • Remote: {remote_status}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    except ConnectionError:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"Connection error to {service_url}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )

    except Exception as e:
        elapsed = round((time.monotonic() - start_time) * 1000)
        return _result(
            status="down",
            response_time_ms=elapsed,
            detail=f"{service_name} error: {e}",
            timestamp=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        )


def _result(status: str, response_time_ms: int, detail: str, timestamp: str) -> dict:
    """Create standardized service check result."""
    return {
        "status": status,
        "response_time_ms": response_time_ms,
        "detail": detail if detail else None,
        "timestamp_utc": timestamp,
    }
```

### Key Design Choices

| Setting | Purpose | Recommendation |
|---------|---------|----------------|
| `status="up"` with no config | Machine intentionally has no service | **Use this** (machine is not broken) |
| `status="down"` with error | Connection failure or API error | Use for genuine failures |
| `timeout_ms` | HTTP request timeout in milliseconds | ~1500ms recommended for API checks |

---

## Step 2: Update Configuration Files

### `config.py` Additions

Add credentials section for your service (if needed):

```python
# ------ Service Name Configuration ------
SERVICE_CONFIG = {
    "surface3-gc": {
        "service_url": "http://surface3-gc:32400",
        "service_token": "your_secret_token",
    },
    "mathes-mac-mini": None,  # Machine without this service
    # Include ALL machines from FLEET so unknowns map to None gracefully
}
```

Add machine entry in FLEET (if new machine):

```python
{
    "display_name": "Service Name Server",
    "tailscale_name": "machine-name",
    "tailscale_ip": "100.x.x.x",
    "primary_role": "Service Role",
    "probe_port": 32400,  # Port for TCP reachability check
    "services": [
        {
            "name": "ServiceName",
            "port": 32400,  # Same port usually as probe_port
            "priority": "P",  # P, B1, B2, etc. (visual ordering)
            "check_type": "{service_name_checker}",  # Must match file name without _checker.py
            "public_url": None,  # For Layer 3 public endpoint checks; null for Tailscale-only
        },
    ],
},
```

**Note:** `check_type` value must exactly match the word in your filename: `{service_name}_checker.py` → `check_type: "{service_name}"`

### `engine.py` Update

Locate the `services` property and create a new service entry under the appropriate section (Layer 2 internal services or Layer 3 public endpoints).

---

## Step 3: Update Test Script (For Testing)

Update `test_checker.py` to import your checker module:

```python
from checkers import tcp_checker, http_checker
from checkers import ollama_checker, comfyui_checker, openwebui_checker, flask_checker, plex_checker, {YOUR_CHECKER}_checker
```

Then add to the checker map for service checks:

```python
    checker_map = {
        "ollama": ollama_checker,
        "comfyui": comfyui_checker,
        "openwebui": openwebui_checker,
        "flask": flask_checker,
        "plex": plex_checker,
        "{YOUR_CHECKER}": {YOUR_CHECKER}_checker,  # Add your checker
    }
```

---

## Step 4: Install Dependencies

Run on any machine that will execute the checker (typically Amsterdam):

```bash
pip install {DEP1} {DEP2} ...
```

For Plex: `pip install plexapi`

Dependencies are Python packages imported at runtime. They must be installed on every host running the service checker.

---

## Step 5: Testing

Run diagnostic test for your specific machine:

```bash
python3 test_checker.py --machine {tailscale_name}
```

Expected output format:

```
{Display Name}:
  [PASS] {Service Name} :{port} [{check_type}] — up {ms}ms — {detail string}
  
  (If no config exists for machine:)
  [PASS] {Service Name} :{port} [{check_type}] — up {ms}ms — No {service_name} config for {tailscale_name}
```

**Pass Criteria:**
- `[PASS]` status appears in output
- `status: "up"` in response_time_ms field
- Detail string is informative but not empty

---

## Best Practices & Tips

1. **Detail String Format**: 
   - Show key status info (version, state, count) separated by ` • `
   - Use newlines (`\n`) for multiline details when showing lists
   - Never leave detail blank on success

2. **Error Handling**:
   - Catch specific exceptions first (ConnectionError, ConnectTimeout)
   - Catch generic Exception last with traceback info stripped

3. **Config Coverage**:
   - Always include ALL machines in SERVICE_CONFIG dict
   - Use `None` for machines without the service instead of omitting them
   - This prevents "configuration not found" errors appearing as failures

4. **Performance**:
   - Calculate elapsed time after successful API calls, not before
   - Keep timeout_ms reasonable (1000-3000ms typical)
   - Don't make multiple API calls in loop for simple health checks

5. **Naming Conventions**:
   - File: `{service_name}_checker.py`
   - Check type in config: `check_type: "{service_name}"` (same without extension)
   - Import variable: `{service_name}_checker`

---

## Checklist for Adding a New Checker

- [ ] Created `checkers/{service_name}_checker.py` with standard structure
- [ ] Added to `Checker.map()` in `test_checker.py`
- [ ] Defined credentials/config in `config.py` (SERVICE_CONFIG)
- [ ] Added machine entry to FLEET list (if new machine)
- [ ] Set correct `check_type` value matching file name
- [ ] Installed any Python dependencies on checker host
- [ ] Tested with `python3 test_checker.py --machine {name}`

---

## Example Files Referenced

| File | Purpose |
|------|---------|
| `config.py` | Machine list, credentials, ports, check configs |
| `checkers/plex_checker.py` | Example service checker module |
| `test_checker.py` | Diagnostic test runner |
| `engine.py` | Production monitoring loop (if Layer 2/3 checks needed in engine) |

*Last updated: 2025-03-10 — Based on Plex Server implementation*
