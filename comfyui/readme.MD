# ComfyUI Fleet Management Scripts

Scripts for managing a multi-machine ComfyUI setup — scanning models, custom nodes,
and workflow dependencies across the fleet, then running cross-machine gap analysis on macOS.

---

## TL;DR — The Whole Thing in 6 Lines

```
1. Double-click Run-FleetScan-[MACHINE].bat on each Windows machine
2. Run ~/repos/scripts/comfyui/comfy_fleet.sh on Mac
3. Open fleet-output/fleet_report_*.html in browser
4. Copy sync_ModelsBase_MIN.bat to ImageBeast and double-click it
5. Install missing nodes on TravelBeast via ComfyUI Manager
6. Repeat monthly or before a trip
```

---

## When To Run This

- Before/after adding new models to any machine
- Before a trip (check TravelBeast readiness)
- Monthly to track drift
- After installing new custom nodes

---

## The Fleet

| Machine       | GPU  | VRAM | Role                             |
|---------------|------|------|----------------------------------|
| IMAGEBEAST    | 5090 | 32GB | Source of truth, runs everything |
| CHATWORKHORSE | 3060 | 12GB | Shares Models_bare w/ Travel     |
| TRAVELBEAST   | 5060 |  8GB | Shares Models_bare w/ Chat       |

**Models_bare** is an OneDrive folder junctioned into ComfyUI on both Chat and Travel:
- `C:\Users\pc\...\0ComfyUI\Models_bare` (ChatWorkhorse)
- `C:\Users\DrDen\...\0ComfyUI\Models_bare` (TravelBeast)
- Same OneDrive folder, different local paths. Adding a model to one adds it to both.

**Workflow naming convention:**
- `###tb` — TravelBeast variant (uses Models_bare paths)
- `###c`  — ChatWorkhorse variant (uses Models_bare paths)
- `###i`  — ImageBeast only (large models, high VRAM)
- `###`   — no suffix, typically ImageBeast default

**000 Starting Images folder** (`workflows/000 Starting Images`):
- Contains one PNG per prime `tb` workflow, named identically to the workflow
- Each PNG has the workflow embedded — drag onto ComfyUI canvas to load it
- Used by the fleet report as the definitive travel readiness check

---

## All Files and Where They Live

### On Each Windows Machine — `C:\repos\scripts\comfyui\`

| File | Purpose |
|------|---------|
| `Get-CustomNodes.ps1` | Scans `custom_nodes` directory |
| `Get-Models.ps1` | Scans models directory, outputs CSV |
| `Get-WorkflowModelMap.ps1` | Maps workflows and PNGs to model references |
| `Run-FleetScan-IMAGEBEAST.bat` | Wrapper — just double-click this |
| `Run-FleetScan-CHATWORKHORSE.bat` | Wrapper — just double-click this |
| `Run-FleetScan-TRAVELBEAST.bat` | Wrapper — just double-click this |
| `README.md` | This file |
| `fleet_config_reference.md` | Config file field reference |

### On OneDrive (shared, all machines) — `0ComfyUI\Work\comfy-reports\`

| File/Folder | Purpose |
|-------------|---------|
| `fleet_config.json` | Machine config, paths, VRAM settings |
| `IMAGEBEAST-*.csv / .txt` | Latest scan reports from ImageBeast |
| `CHATWORKHORSE-*.csv / .txt` | Latest scan reports from ChatWorkhorse |
| `TRAVELBEAST-*.csv / .txt` | Latest scan reports from TravelBeast |
| `fleet-output/fleet_report_*.html` | **Open this in browser** |
| `fleet-output/summary_*.txt` | Plain text summary |
| `fleet-output/custom_nodes_*.txt` | Node comparison matrix |
| `fleet-output/sync_ModelsBase_MIN.bat` | Copy to ImageBeast and run |
| `fleet-output/sync_ModelsBase_MAYBE.bat` | Optional — larger marginal models |
| `fleet-output/subdir_mismatches_*.txt` | Models in wrong subdirs vs ImageBeast |
| `fleet-output/fix_subdir_structure.bat` | Robocopy to fix subdir mismatches |
| `history/snapshot-*.json` | Drift detection history — do not delete |

### On Mac — `~/repos/scripts/comfyui/`

| File | Purpose |
|------|---------|
| `comfy_fleet.py` | Main analysis script |
| `comfy_fleet.sh` | Shell wrapper — run this |

---

## Step 1 — Run Scan on Each Windows Machine

Just double-click the batch file for that machine. No need to open PowerShell manually.

Each scan takes 5–15 minutes (ImageBeast longest due to PNG scanning).
Reports save automatically to the shared OneDrive `comfy-reports` folder.

You don't need to run all three machines the same day — the analysis always uses
the newest report per machine.

### What the batch files actually run (for reference / manual use)

#### IMAGEBEAST
```
cd C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI

C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

C:\repos\scripts\comfyui\Get-Models.ps1 -ModelsPath "C:\ComfyUI_Models\models"

C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 `
    -ModelsPath "C:\ComfyUI_Models\models" `
    -WorkflowDir .\user\default\workflows\ `
    -PngDir "C:\Users\Pc\OneDrive\...\0ComfyUI\output\" `
    -StartingPrimesDir "C:\Users\Pc\OneDrive\...\0ComfyUI\workflows\000 Starting Images"
```

#### TRAVELBEAST
```
cd C:\ComfyUI-Easy-Install\ComfyUI

C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

C:\repos\scripts\comfyui\Get-Models.ps1 `
    -ModelsPath "C:\Users\DrDen\OneDrive\...\0ComfyUI\Models_bare"

C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 `
    -ModelsPath "C:\Users\DrDen\OneDrive\...\0ComfyUI\Models_bare" `
    -WorkflowDir .\user\default\workflows\ `
    -PngDir "C:\Users\DrDen\OneDrive\...\0ComfyUI\output\" `
    -StartingPrimesDir "C:\Users\DrDen\OneDrive\...\0ComfyUI\workflows\000 Starting Images"
```

#### CHATWORKHORSE
```
cd C:\ComfyUI_windows_portable\ComfyUI

C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

C:\repos\scripts\comfyui\Get-Models.ps1 `
    -ModelsPath "C:\Users\pc\OneDrive\...\0ComfyUI\Models_bare"

C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 `
    -ModelsPath "C:\Users\pc\OneDrive\...\0ComfyUI\Models_bare" `
    -WorkflowDir .\user\default\workflows\ `
    -PngDir "C:\Users\Pc\OneDrive\...\0ComfyUI\output\" `
    -StartingPrimesDir "C:\Users\Pc\OneDrive\...\0ComfyUI\workflows\000 Starting Images"
```

---

## Step 2 — Run Analysis on Mac

```bash
~/repos/scripts/comfyui/comfy_fleet.sh
```

Or with a year override:
```bash
~/repos/scripts/comfyui/comfy_fleet.sh --year 2025
```

Output goes to `comfy-reports/fleet-output/`. Open the HTML report in a browser.

---

## Step 3 — Act on the Results

### A) Sync Models to Models_bare (run on IMAGEBEAST)

```
fleet-output\sync_ModelsBase_MIN.bat     <- run this first (safe for 8GB VRAM)
fleet-output\sync_ModelsBase_MAYBE.bat   <- optional, 8-12GB models
```

Robocopy copies from `C:\ComfyUI_Models\models\` into `Models_bare`.
OneDrive then syncs automatically to TravelBeast and ChatWorkhorse.

> **Note:** Uses `/COPY:DAT` flag (Data, Attributes, Timestamps).
> Do NOT use `/COPYALL` — it requires special Windows audit privileges and will fail.

### B) Fix Subdir Structure Mismatches

If the report shows mismatches (models in wrong subdirectories vs ImageBeast):

```
fleet-output\fix_subdir_structure.bat
```

This copies files to the correct subdir location. **Does not delete originals** — verify
first, then manually delete the old copies.

### C) Install Missing Custom Nodes

Open ComfyUI -> Manager -> Install Missing Nodes.
See `fleet-output/custom_nodes_*.txt` for the full matrix of what's missing where.

---

## HTML Report Sections Explained

| Section | What it shows |
|---------|---------------|
| **Next Actions** | Prioritized to-do list — !!! high, ! medium, blank low |
| **Travel / Workflow Readiness** | % of current-year workflows runnable per machine |
| **Model Drift** | What changed since last run (models added/removed) |
| **Model Gaps** | What's missing from Models_bare vs ImageBeast |
| **Custom Nodes — Fleet Matrix** | Which nodes are on which machines |
| **Unused Models on ImageBeast** | Models on disk never referenced in any workflow |
| **Subdir Structure Mismatches** | Models at wrong paths vs ImageBeast structure |
| **Starting Images — Travel Readiness** | Per-PNG readiness for your curated tb prime set |
| **Current Year Workflow Coverage** | All current-year workflows across fleet, all machines |

---

## Sample Output — What Success Looks Like

### Get-WorkflowModelMap.ps1 (with StartingPrimesDir)

```
Scanning Starting Images (prime set) in: C:\...\workflows\000 Starting Images
  Found 42 PNG file(s)
  SKIPPED (no workflow data): 703_tb_Upscale_none.png    <- fine, no-model workflows
  SKIPPED (no workflow data): 810_tb_RemoveBackground_none.png
  Prime processed : 37  |  Skipped (no workflow data): 5
```

### comfy_fleet.sh (Mac) — healthy fleet

```
ComfyUI Fleet Analysis  2026-04-09
Year filter: 2026
============================================================
READINESS
------------------------------------------------------------
  IMAGEBEAST        87%  (795/914 workflows)  32GB VRAM
  CHATWORKHORSE     58%  (528/914 workflows)  12GB VRAM  <- expected, VRAM-limited
  TRAVELBEAST       58%  (526/912 workflows)   8GB VRAM  <- expected, VRAM-limited

STARTING IMAGES -- TRAVEL READINESS
------------------------------------------------------------
  TRAVELBEAST: READY  (19 models present, 0 missing)

NEXT ACTIONS
------------------------------------------------------------
  [!!!]  Run sync_ModelsBase_MIN.bat on ImageBeast
  [ ! ]  Install missing nodes on TravelBeast via ComfyUI Manager
  [   ]  Review unused models on ImageBeast
```

> **Note on Chat/Travel readiness %:** 58% is expected — blocked workflows require large
> models (flux1-fill-dev 22GB, Qwen-Rapid-AIO 26GB) that won't fit in 8-12GB VRAM.
> Those are ImageBeast-only by design.

---

## Known Issues / Notes

- **`.cache` access denied** on ImageBeast: harmless — Hugging Face cache folder inside
  `dreamomni2`. All models still found correctly.

- **Bad JSON skips**: corrupt or non-standard workflow files. Safe to ignore.

- **Chat and Travel show identical model counts**: by design — they share the same
  OneDrive `Models_bare` folder via Windows junction (`mklink /j`).

- **"Missing models" count is large on ImageBeast**: mostly path-format variants
  (e.g. `FLUX2\model.safetensors` vs `model.safetensors`), not genuine gaps.

- **PS1 files won't open on double-click**: Windows security feature. Use the
  `.bat` wrappers instead.

- **robocopy flag**: always use `/COPY:DAT` not `/COPYALL`.
  `/COPYALL` requires audit privileges that even admin accounts don't have by default.

- **Starting Images PNGs with `_none` in name**: skipped because they have no model
  references (resize/remove background workflows). This is correct — they will always
  run regardless of model state.

- **Subdir mismatches**: models exist on Models_bare but at different paths than
  ImageBeast. Workflows may fail to find them until `fix_subdir_structure.bat` is run.
  Post-trip cleanup item.
