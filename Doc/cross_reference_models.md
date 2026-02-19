# ComfyUI Models Cross-Reference Tool

This script analyzes the relationship between your ComfyUI model inventory (what you have installed) and your workflow references (what your workflows actually use). It helps you identify missing models, unused models, and optimize your storage.

## Purpose

Cross-reference two CSV files to find:
- **Missing Models** - Referenced in workflows but not in your inventory (broken workflows!)
- **Unused Models** - In your inventory but never referenced (potential space savings)
- **Used Models** - Successfully matched models with usage statistics

## Requirements

Python 3.6 or higher (no additional packages needed)

## Usage

### Basic Usage

```bash
python cross_reference.py models_inventory.csv workflow_references.csv
```

This creates four report files in the current directory:
- `missing_models.csv` - Models needed by workflows but not found
- `unused_models.csv` - Models installed but never used
- `used_models.csv` - Models that are actively used
- `summary.txt` - Text summary of the analysis

### Specify Output Directory

```bash
python cross_reference.py models_inventory.csv workflow_references.csv -o reports
```

### Disable Fuzzy Matching

By default, the script uses fuzzy matching to handle path differences (e.g., `FLUX\model.safetensors` vs `FLUX/model.safetensors`). To require exact matches:

```bash
python cross_reference.py models_inventory.csv workflow_references.csv --no-fuzzy-match
```

### Complete Workflow Example

```bash
# Step 1: Generate models inventory from directory listing
dir /s > models_lst.txt
python scan_models.py models_lst.txt -o models_inventory.csv

# Step 2: Scan workflows for model references
python scan_safetensors.py C:\ComfyUI\output -o workflow_references.csv

# Step 3: Cross-reference to find mismatches
python cross_reference.py models_inventory.csv workflow_references.csv -o reports
```

## Output Reports

### 1. missing_models.csv

Models that are referenced in your workflows but NOT in your inventory.

**Columns:**
- `referenced_file` - The safetensor filename referenced in the workflow
- `workflow_file` - Which workflow file references it
- `workflow_directory` - Where the workflow is located
- `node_name` - Which node is trying to use this model

**Example:**
```csv
referenced_file,workflow_file,workflow_directory,node_name
old_model_v3.safetensors,my_workflow.json,C:\ComfyUI\workflows,CheckpointLoaderSimple
```

**Action:** These are broken references. You need to either:
- Download the missing models
- Update your workflows to use available models
- Remove/fix the workflows

### 2. unused_models.csv

Models in your inventory that are NEVER referenced in any workflow.

**Columns:**
- `filename` - The safetensor filename
- `directory` - Where it's stored
- `file_date` - When it was last modified
- `size_gb` - File size in gigabytes

**Example:**
```csv
filename,directory,file_date,size_gb
old_checkpoint.safetensors,C:\ComfyUI_Models\models\checkpoints,01/15/2026 03:30 PM,6.46
```

**Action:** Consider deleting these to free up space. The report shows total GB that could be recovered.

### 3. used_models.csv

Models that are in your inventory AND actively used in workflows.

**Columns:**
- `filename` - The safetensor filename
- `directory` - Where it's stored
- `size_gb` - File size in gigabytes
- `reference_count` - How many times it's referenced
- `workflows` - Which workflow files use it

**Example:**
```csv
filename,directory,size_gb,reference_count,workflows
flux1-dev-fp8.safetensors,C:\ComfyUI_Models\models\checkpoints\FLUX,16.06,5,"workflow1.json, workflow2.json"
```

**Action:** These are your actively used models. Keep these!

### 4. summary.txt

Human-readable summary with key statistics.

**Example:**
```
======================================================================
ComfyUI Models Cross-Reference Summary
======================================================================

INVENTORY STATISTICS
----------------------------------------------------------------------
Total models in inventory:        104
Models used in workflows:         35
Models never referenced:          69

WORKFLOW STATISTICS
----------------------------------------------------------------------
Unique models referenced:         35
Total model references:           127
Models referenced but missing:    0

STORAGE ANALYSIS
----------------------------------------------------------------------
Space used by unused models:      285.50 GB
```

## Fuzzy Matching

The script uses intelligent fuzzy matching to handle:

- **Path separator differences**: `FLUX\model.safetensors` matches `FLUX/model.safetensors`
- **Case differences**: `Model.safetensors` matches `model.safetensors`
- **Subdirectory paths**: `FLUX\models\flux.safetensors` matches just `flux.safetensors`

This accounts for how ComfyUI might store paths differently in workflows vs. directory listings.

**Disable fuzzy matching** if you want strict exact matches only:
```bash
python cross_reference.py models.csv workflows.csv --no-fuzzy-match
```

## Use Cases

### Identify Broken Workflows
```bash
python cross_reference.py models_inventory.csv workflow_references.csv -o reports
# Check reports/missing_models.csv for models you need to download
```

### Free Up Disk Space
```bash
python cross_reference.py models_inventory.csv workflow_references.csv -o reports
# Check reports/unused_models.csv and reports/summary.txt
# The summary shows total GB you can recover by deleting unused models
```

### Audit Model Usage
```bash
python cross_reference.py models_inventory.csv workflow_references.csv -o reports
# Check reports/used_models.csv to see which models are most used
# Sort by reference_count to find your most popular models
```

### Before/After Cleanup
```bash
# Before cleanup
python cross_reference.py models_inventory.csv workflow_references.csv -o reports_before

# Delete some unused models
# Re-generate inventory
dir /s > models_lst.txt
python scan_models.py models_lst.txt -o models_inventory_new.csv

# After cleanup
python cross_reference.py models_inventory_new.csv workflow_references.csv -o reports_after

# Compare the summaries to see space saved
```

## Understanding the Output

### ✓ Good Signs
- `No missing models` - All workflow references are satisfied
- High percentage of used models - You're efficiently using your storage
- No missing models with large unused models - Easy cleanup opportunity

### ⚠ Warning Signs
- Missing models - Workflows will fail
- Large number of unused models with high GB - Wasted storage
- Models referenced but missing - Need to fix workflows or find models

## Tips for Best Results

1. **Keep workflows updated** - Scan your workflow directory regularly
2. **Update inventory after changes** - Re-run `scan_models.py` after adding/removing models
3. **Use fuzzy matching** - It handles path format differences automatically
4. **Check missing_models first** - These are the most critical issues
5. **Review unused models by size** - Sort by size_gb to find the biggest space savings

## Example Session

```bash
# Generate reports
$ python cross_reference.py models_inventory.csv workflow_references.csv -o reports

======================================================================
ComfyUI Models Cross-Reference Analysis
======================================================================

Models inventory:     models_inventory.csv
Workflow references:  workflow_references.csv
Output directory:     reports
Fuzzy matching:       Enabled

----------------------------------------------------------------------

Loading data...
  Loaded 104 models from inventory
  Loaded 35 unique model references from workflows

Generating reports...

✓ No missing models - all workflow references found in inventory!

📊 Unused models report: reports/unused_models.csv
   Found 69 models in inventory but NOT referenced in workflows
   Total size of unused models: 285.50 GB

✓ Used models report: reports/used_models.csv
   Found 35 models actively used in workflows

📄 Summary report: reports/summary.txt

======================================================================
Analysis Complete!
======================================================================

All reports saved to: reports
```

## Troubleshooting

**"No missing models" but I know some are missing:**
- Check if fuzzy matching is too permissive
- Try `--no-fuzzy-match` for exact matching
- Verify your workflow_references.csv was generated from the right directory

**"All models showing as unused":**
- Verify your workflow_references.csv was generated correctly
- Check that workflow files actually have embedded workflow data
- Ensure you scanned the right workflow directory

**Path format issues:**
- Fuzzy matching should handle this automatically
- Windows backslashes vs forward slashes are normalized
- If issues persist, check the CSV files directly for the exact format

## Integration with Other Tools

This tool is designed to work with:
- **scan_models.py** - Creates the models inventory CSV
- **scan_safetensors.py** - Creates the workflow references CSV

All three tools use compatible CSV formats for seamless integration.
