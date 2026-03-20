# Fleet Checker — Config Maintenance Cheatsheet

## File to edit: `config.py` — FLEET list

---

## Machine entry structure

```python
{
    "display_name": "ImageBeast",          # shown in dashboard UI
    "tailscale_name": "imagebeast",        # Tailscale MagicDNS short name
    "tailscale_ip": "100.107.247.38",      # Tailscale IP (for reference only)
    "primary_role": "ComfyUI Primary",     # shown in dashboard UI
    "probe_port": 8188,                    # port used for Layer 1 TCP host check
                                           # pick whichever service is most reliably running
    "services": [ ... ]
}
```

---

## Service entry structure

```python
{
    "name": "ComfyUI",                     # shown in dashboard UI
    "port": 8188,                          # port on that machine
    "priority": "P",                       # P / B2 / B5 / B9 / B99
    "check_type": "comfyui",               # see check types below
    "public_url": "https://image.ldmathes.cc",  # Cloudflare public URL, or None
}
```

---

## Check types

| check_type | What it does |
|------------|-------------|
| `ollama`   | GET /api/tags + GET /api/ps — model count + active VRAM model |
| `comfyui`  | GET /system_stats + GET /queue — GPU, VRAM, queue depth |
| `openwebui`| GET /health — returns healthy/unhealthy |
| `flask`    | GET / — any HTTP response = alive |
| `tcp`      | TCP connect only — no HTTP, just port open/closed |

---

## Priority codes

| Code | Meaning |
|------|---------|
| `P`  | Primary — intended host under normal conditions |
| `B2` | Real backup — expected to work reliably |
| `B5` | Capable but not preferred |
| `B9` | Last resort on this network |
| `B99`| Theoretical only — software installed but not a real fallback |

---

## Common tasks

### Remove a service from a machine
Delete the entire `{ ... }` service block from that machine's `"services"` list.

### Add a service to a machine
Add a new `{ ... }` block to the `"services"` list. Pick the correct `check_type`.

### Change a public Cloudflare URL
Edit the `"public_url"` value. Set to `None` if no public URL exists.

### Mark a service as Tailscale-only (no public check)
Set `"public_url": None`

### Add a new machine
Add a new `{ ... }` block to the `FLEET` list. Follow the machine entry structure above.
Set `probe_port` to whichever service port is most reliably running on that machine.

### Change a machine's Tailscale IP
Edit `"tailscale_ip"`. Note: the checker uses MagicDNS name for connections,
not the IP — the IP field is for reference/display only.

### Change probe_port
Edit `"probe_port"`. Use whichever service is most reliably always running.
This is only used for Layer 1 host reachability — if this port is down,
all services on that machine are marked unknown.

---

## Current fleet — quick reference

| Machine | tailscale_name | probe_port | Services |
|---------|---------------|------------|---------|
| ImageBeast | imagebeast | 8188 | ComfyUI(P), Ollama(B2), OpenWebUI(B2) |
| ChatWorkhorse | chatworkhorse | 11434 | ComfyUI(B2), Ollama(P), OpenWebUI(P) |
| TravelBeast | travelbeast | 8188 | ComfyUI(B5), Ollama(B5) |
| Amsterdam | amsterdamdesktop | 5000 | ComfyUI(B9), Ollama(B9), Flask/API(P), Flask/API-Edit(P), Flask/Weather(P), OpenWebUI(P), Fleet API(P) |
| MacBook Air Prime | denniss-macbook-air | 11434 | Ollama(B99) |
| MacBook Air 2 | denniss-2nd-macbook-air | 11434 | Ollama(B99) |

---

## Current Cloudflare public URLs

| URL | Machine | Service |
|-----|---------|---------|
| https://image.ldmathes.cc | ImageBeast | ComfyUI |
| https://clips.ldmathes.cc | ChatWorkhorse | ComfyUI |
| https://ollama.ldmathes.cc | ChatWorkhorse | Ollama |
| https://api.ldmathes.cc | Amsterdam | Flask/API |
| https://api-edit.ldmathes.cc | Amsterdam | Flask/API-Edit |
| https://weatherproxy.ldmathes.cc | Amsterdam | Flask/Weather |
| https://chat.ldmathes.cc | Amsterdam | OpenWebUI |
| https://fleet.ldmathes.cc | Amsterdam | Fleet API (Phase 2) |
| https://fleet-bkp.ldmathes.cc | ChatWorkhorse | Fleet API (Phase 2) |

---

## Fix: ImageBeast OpenWebUI

ImageBeast currently has OpenWebUI listed as B2 but it is not running there.
Either remove it or change priority to reflect reality:

**Remove it** — delete this block from ImageBeast services:
```python
{
    "name": "OpenWebUI",
    "port": 8080,
    "priority": "B2",
    "check_type": "openwebui",
    "public_url": None,
},
```

**Or keep it** with a lower priority if you plan to deploy it there eventually.
