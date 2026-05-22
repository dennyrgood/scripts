# fleet_config.json — Field Reference

Configuration file for `comfy_fleet.py`. Lives in the `comfy-reports` folder on OneDrive
so all machines can access it.

Location: `0ComfyUI\Work\comfy-reports\fleet_config.json`

---

## Top-Level Paths

```json
"reports_dir": "/Users/dennishmathes/OneDrive/.../comfy-reports"
```
Where the PS1 scan reports land (CSVs and TXTs). Must be the Mac path.
**Change if:** you move your OneDrive folder or rename the reports directory.

```json
"output_dir": "/Users/dennishmathes/OneDrive/.../comfy-reports/fleet-output"
```
Where `comfy_fleet.py` writes its outputs (HTML report, sync scripts, etc.).
**Change if:** you want outputs somewhere other than a subfolder of reports_dir.

```json
"history_dir": "/Users/dennishmathes/OneDrive/.../comfy-reports/history"
```
Where drift detection snapshots are saved. Do not delete files from here — they
are the baseline for "what changed since last run".
**Change if:** you want snapshots stored elsewhere.

```json
"prime_workflows_dir": "/Users/dennishmathes/OneDrive/.../workflows"
```
Root of your prime workflows folder. Scanned for JSON files to build the
Current Year Workflow Coverage report. Mac path.
**Change if:** you move your workflows folder.

```json
"prime_starting_images_dir": "/Users/dennishmathes/OneDrive/.../workflows/000 Starting Images"
```
The curated `tb` PNG set used for Starting Images — Travel Readiness report.
PNGs here must have embedded ComfyUI workflows (produced by running workflows
and saving output PNGs, then renaming them to match the workflow filename).
**Change if:** you rename or move the 000 Starting Images folder.

---

## machines

One entry per machine. The key is the Windows hostname (must match `$env:COMPUTERNAME`).

```json
"IMAGEBEAST": {
    "vram_gb":     32,
    "is_source":   true,
    "models_root": "C:\\ComfyUI_Models\\models",
    "models_bare": null,
    "comfy_root":  "C:\\ComfyUI_easy\\ComfyUI-Easy-Install\\ComfyUI",
    "png_dir":     "C:\\Users\\Pc\\OneDrive\\...\\output"
}
```

| Field | Purpose | Change if... |
|-------|---------|--------------|
| `vram_gb` | GPU VRAM in GB. Controls MIN/MAYBE sync thresholds | You upgrade your GPU |
| `is_source` | `true` = this machine is the model source of truth | You change which machine is master |
| `models_root` | Full path to models directory on this machine | You move your models |
| `models_bare` | Path to Models_bare folder (null for source machine) | OneDrive path changes |
| `sync_group` | Group key for shared Models_bare — machines with same group share one sync script | Never change unless restructuring |
| `comfy_root` | ComfyUI installation root | You reinstall ComfyUI elsewhere |
| `png_dir` | Output PNG folder scanned for embedded workflows | You change your output folder |

> **Warning:** Only one machine should have `"is_source": true`. This machine's
> model list is the reference for gap analysis and robocopy source paths.

---

## vram_thresholds

```json
"vram_thresholds": {
    "ok":    8.0,
    "maybe": 12.0
}
```

Controls how models are categorized for the sync scripts:

| Category | Size | Sync script |
|----------|------|-------------|
| **MIN** (safe) | <= `ok` GB | `sync_ModelsBase_MIN.bat` — always run this |
| **MAYBE** (marginal) | `ok` to `maybe` GB | `sync_ModelsBase_MAYBE.bat` — test before travelling |
| **BIG** (skip) | > `maybe` GB | Not synced — too large for travel/chat machines |

**Change if:** you upgrade TravelBeast or ChatWorkhorse and can handle larger models.

---

## workflow_year_filter

```json
"workflow_year_filter": "2026"
```

Controls which workflows are counted for the readiness % and Current Year
Workflow Coverage report. Matches against the `workflow_modified` date in the CSV.

**Change to:** `"2025"` to analyze last year, or `"2027"` next year.

Can also be overridden at runtime without editing the file:
```bash
./comfy_fleet.sh --year 2025
```

---

## sync

```json
"sync": {
    "source_machine":     "IMAGEBEAST",
    "source_models_root": "C:\\ComfyUI_Models\\models",
    "dest_models_bare":   "C:\\Users\\Pc\\OneDrive\\...\\Models_bare"
}
```

Used to build the robocopy scripts.

| Field | Purpose | Change if... |
|-------|---------|--------------|
| `source_machine` | Which machine's models are copied FROM | You change the source machine |
| `source_models_root` | Windows path to source models directory | You move models on ImageBeast |
| `dest_models_bare` | Windows path to Models_bare destination | OneDrive path changes on ImageBeast |

> **Warning:** `dest_models_bare` is the ImageBeast-side path to the OneDrive
> folder. OneDrive syncs this to TravelBeast and ChatWorkhorse automatically.
> Do not set this to a TravelBeast or ChatWorkhorse path.

---

## Adding a New Machine

1. Add a new entry under `machines` with the correct hostname
2. Set `vram_gb`, `is_source: false`, `models_bare` path, `sync_group`
3. If it shares Models_bare with existing machines, give it the same `sync_group` value
4. Create a new `Run-FleetScan-NEWMACHINE.bat` and deploy it
5. Run the fleet scan on the new machine
6. Run `comfy_fleet.sh` — it will auto-discover the new machine's reports

---

## Changing the Year Filter

Edit `workflow_year_filter` in the config, or pass `--year YYYY` to `comfy_fleet.sh`.
The filter matches the start of the `workflow_modified` field in the CSV
(e.g. `"2026"` matches any date starting with `2026-`).
