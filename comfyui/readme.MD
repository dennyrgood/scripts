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

| Machine       | GPU  | VRAM | Models | Role                          |
|---------------|------|------|--------|-------------------------------|
| IMAGEBEAST    | 5090 | 32GB | 147    | Source of truth, runs everything |
| CHATWORKHORSE | 3060 | 12GB |  41    | Shares Models_bare w/ Travel  |
| TRAVELBEAST   | 5060 |  8GB |  41    | Shares Models_bare w/ Chat    |

**Models_bare** is an OneDrive folder junctioned into ComfyUI on both Chat and Travel:
- `C:\Users\pc\...\0ComfyUI\Models_bare` (ChatWorkhorse)
- `C:\Users\DrDen\...\0ComfyUI\Models_bare` (TravelBeast)
- Same OneDrive folder, different local paths. Adding a model to one adds it to both.

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
    -PngDir "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output\"
```

#### TRAVELBEAST
```
cd C:\ComfyUI-Easy-Install\ComfyUI

C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

C:\repos\scripts\comfyui\Get-Models.ps1 `
    -ModelsPath "C:\Users\DrDen\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare"

C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 `
    -ModelsPath "C:\Users\DrDen\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare" `
    -WorkflowDir .\user\default\workflows\ `
    -PngDir "C:\Users\DrDen\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output\"
```

#### CHATWORKHORSE
```
cd C:\ComfyUI_windows_portable\ComfyUI

C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

C:\repos\scripts\comfyui\Get-Models.ps1 `
    -ModelsPath "C:\Users\pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare"

C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 `
    -ModelsPath "C:\Users\pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare" `
    -WorkflowDir .\user\default\workflows\ `
    -PngDir "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\output\"
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
fleet-output\sync_ModelsBase_MIN.bat     ← run this first (safe for 8GB VRAM)
fleet-output\sync_ModelsBase_MAYBE.bat   ← optional, 8–12GB models
```

Robocopy copies from `C:\ComfyUI_Models\models\` into `Models_bare`.
OneDrive then syncs automatically to TravelBeast and ChatWorkhorse.

> **Note:** Uses `/COPY:DAT` flag (Data, Attributes, Timestamps).
> Do NOT use `/COPYALL` — it requires special Windows audit privileges and will fail.

### B) Install Missing Custom Nodes

Open ComfyUI → Manager → Install Missing Nodes.
See `fleet-output/custom_nodes_*.txt` for the full matrix of what's missing where.

**Priority nodes to install on TravelBeast:**
- `comfyui-qwenvl` — Qwen Vision Language nodes (used heavily)
- `comfyui_ipadapter_plus` — IPAdapter face/style transfer
- `was-ns` — WAS Node Suite, used in many workflows
- `vantage-dreamomni2` — DreamOmni2 image editing
- `comfyui_layerstyle` — layer compositing, blend modes
- `comfyui-advancedliveportrait` — portrait animation

---

## Sample Output — What Success Looks Like

### Get-CustomNodes.ps1

```
=============================================
  ComfyUI Custom Nodes Inventory
  Host : IMAGEBEAST
  Root : .
=============================================

Found 46 custom node(s):

  1. .disabled
  2. __pycache__
  3. cocotools_io
  ...
 44. Vantage-DreamOmni2
 45. was-ns
 46. zhihui_nodes_comfyui

Total: 46 custom nodes

Saved: .\comfy-reports\IMAGEBEAST-CustomNodes-2026-04-07_0954.txt
```

### Get-Models.ps1

```
=============================================
  ComfyUI Models Inventory
  Host : IMAGEBEAST
  Root : C:\ComfyUI_Models\
=============================================

Scanning models...

⚠ This error can be ignored — it's a Hugging Face cache folder, not a model:
  Get-ChildItem : Access to the path 'C:\ComfyUI_Models\models\dreamomni2\.cache' is denied.

Found 147 model file(s)

  checkpoints       14 file(s)    112.71 GB
  clip               1 file(s)      0.80 GB
  clip_vision        5 file(s)     15.25 GB
  controlnet         4 file(s)      3.37 GB
  diffusion_models  20 file(s)    278.84 GB
  ...
  TOTAL            147 file(s)    613.25 GB

Saved: .\comfy-reports\IMAGEBEAST-Models-2026-04-07_0958.csv
```

### Get-WorkflowModelMap.ps1

```
=============================================
  ComfyUI Workflow -> Model Map
  Host      : IMAGEBEAST
  Workflows : .\user\default\workflows\
  Models    : C:\ComfyUI_Models\models
=============================================

Building model inventory...
  Found 147 model file(s) on disk

Scanning JSON workflows in: .\user\default\workflows\
  Found 353 JSON file(s)
  SKIP (bad JSON): FaceLock.json          ← these are fine to skip
  SKIP (bad JSON): pluid_fluid_test4.json
  SKIP (bad JSON): pluid_fluid_test5.json
  SKIP (bad JSON): img2img.json
  Processed : 302  |  Skipped: 51

Scanning PNG outputs in: C:\Users\Pc\OneDrive\...\output\
  Found 627 PNG file(s)
  PNG processed : 578  |  Skipped: 105

--- Model Usage Summary (top 20) ---

model_filename                               model_size_gb  workflow_count
--------------                               -------------  --------------
flux2-vae.safetensors                                0.313              70
ae.safetensors                                       0.313              67
clip_l.safetensors                                   0.229              50
qwen_3_4b.safetensors                                7.492              47
flux-2-klein-4b-fp8.safetensors                      3.791              33
...

--- Missing Models (referenced but NOT on disk): 229 ---
  (workflows reference models you don't have — normal for older/downloaded workflows)

--- Unused Models (on disk but NEVER referenced): 70 ---
  (models installed but no workflow uses them — candidates for cleanup)

Output files:
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-full_map.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-model_usage.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-unused_models.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-missing_models.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-summary.txt

Done!
```

### comfy_fleet.sh (Mac)

```
ComfyUI Fleet Analysis  2026-04-07
Year filter: 2026
============================================================
READINESS
------------------------------------------------------------
  IMAGEBEAST        86%  (589/685 workflows)  32GB VRAM
  CHATWORKHORSE     29%  (201/685 workflows)  12GB VRAM  ← expected, VRAM-limited
  TRAVELBEAST       29%  (201/683 workflows)   8GB VRAM  ← expected, VRAM-limited

NEXT ACTIONS
------------------------------------------------------------
  [!!!]  Run sync_ModelsBase_MIN.bat on ImageBeast
         29 files, 58.80 GB
  [ ! ]  Run sync_ModelsBase_MAYBE.bat on ImageBeast
         6 files, 59.34 GB — marginal, test before travelling
  [ ! ]  Install missing nodes on TravelBeast via ComfyUI Manager
         Priority: comfyui-qwenvl, comfyui_ipadapter_plus, was-ns, vantage-dreamomni2
  [   ]  Review unused models on ImageBeast
         Run cleanup to reclaim disk space
```

> **Note on Chat/Travel readiness %:** The 29% figure is not a problem.
> The blocked workflows require models like `flux1-fill-dev` (22GB) or
> `Qwen-Rapid-AIO` (26GB) that won't fit in 8–12GB VRAM regardless.
> Those workflows are ImageBeast-only by design.

---

## Known Issues / Notes

- **`.cache` access denied error** on ImageBeast: harmless. It's a Hugging Face
  model cache folder inside `dreamomni2`. All 147 models are still found correctly.

- **Bad JSON skips**: `FaceLock.json`, `pluid_fluid_test4/5.json`, `img2img.json`
  are corrupt or non-standard workflow files. Safe to ignore.

- **Chat and Travel show identical model counts**: by design — they share the same
  OneDrive `Models_bare` folder via Windows junction (`mklink /j`).

- **"Missing models" count is large**: most are path-format variants of models you
  already have (e.g. `FLUX2\flux2-vae.safetensors` vs `flux2-vae.safetensors`),
  or models from downloaded OpenArt workflows you never installed. Not a real problem.

- **PS1 files won't open on double-click**: Windows security feature. Use the
  `.bat` wrapper files instead — they call PowerShell explicitly.

- **robocopy flag**: always use `/COPY:DAT` not `/COPYALL`.
  `/COPYALL` requires audit privileges that even admin accounts don't have by default.
