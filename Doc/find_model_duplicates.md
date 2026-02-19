# ComfyUI Models Duplicate Finder

This script analyzes your ComfyUI models inventory to find duplicate files based on filename and/or size, helping you identify wasted disk space and potential cleanup opportunities.

## Purpose

Find duplicate models in your ComfyUI installation:
- **Exact Duplicates** - Same filename AND same size (confirmed duplicates)
- **Filename Duplicates** - Same filename but different sizes (different versions)
- **Size Duplicates** - Different filenames but same size (possible duplicates)

Calculate wasted space and identify which duplicates to remove.

## Requirements

Python 3.6 or higher (no additional packages needed)

## Usage

### Basic Usage (Find All Types)

```bash
python find_duplicates.py models_inventory.csv
```

This creates four report files in the current directory:
- `exact_duplicates.csv` - Same name AND size (confirmed duplicates)
- `duplicates_by_name.csv` - Same name, different sizes (versions)
- `duplicates_by_size.csv` - Same size, different names
- `duplicates_summary.txt` - Human-readable summary

### Specify Output Directory

```bash
python find_duplicates.py models_inventory.csv -o duplicate_reports
```

### Find Only Specific Types

```bash
# Find only exact duplicates (most useful)
python find_duplicates.py models_inventory.csv -t exact

# Find only filename duplicates
python find_duplicates.py models_inventory.csv -t name

# Find only size duplicates
python find_duplicates.py models_inventory.csv -t size

# Find all types (default)
python find_duplicates.py models_inventory.csv -t all
```

### Complete Workflow

```bash
# Step 1: Generate models inventory
dir /s > models_lst.txt
python scan_models.py models_lst.txt -o models_inventory.csv

# Step 2: Find duplicates
python find_duplicates.py models_inventory.csv -o duplicate_reports
```

## Output Reports

### 1. exact_duplicates.csv

Files with the SAME filename AND SAME size - these are confirmed duplicates.

**Columns:**
- `filename` - The safetensor filename
- `directory` - Where it's located
- `file_date` - Last modified date
- `size_gb` - File size in GB
- `duplicate_group` - Group number (files with same group are duplicates)
- `instances` - How many copies exist

**Example:**
```csv
filename,directory,file_date,size_gb,duplicate_group,instances
flux1-dev.safetensors,C:\Models\checkpoints,01/12/2026 02:59 PM,22.15,1,2
flux1-dev.safetensors,C:\Models\diffusion_models\FLUX,01/12/2026 02:59 PM,22.15,1,2
```

**Action:** These are safe to delete (keep one copy). The report shows total wasted space.

### 2. duplicates_by_name.csv

Files with the SAME filename but DIFFERENT sizes - likely different versions.

**Columns:**
- `filename` - The safetensor filename
- `directory` - Where it's located
- `file_date` - Last modified date
- `size_gb` - File size in GB
- `duplicate_group` - Group number

**Example:**
```csv
filename,directory,file_date,size_gb,duplicate_group
model_v1.safetensors,C:\Models\old,01/05/2026 10:00 AM,6.46,1
model_v1.safetensors,C:\Models\new,01/20/2026 02:00 PM,7.23,1
```

**Action:** Review carefully - these might be different versions. Keep the one you need.

### 3. duplicates_by_size.csv

Files with the SAME size but DIFFERENT names - possible duplicates or renamed files.

**Columns:**
- `filename` - The safetensor filename
- `directory` - Where it's located
- `file_date` - Last modified date
- `size_gb` - File size in GB
- `size_bytes` - Exact size in bytes
- `duplicate_group` - Group number

**Example:**
```csv
filename,directory,file_date,size_gb,size_bytes,duplicate_group
checkpoint_v1.safetensors,C:\Models\A,01/10/2026,6.46,6938041042,1
checkpoint_v2.safetensors,C:\Models\B,01/15/2026,6.46,6938041042,1
```

**Action:** Investigate - same size might indicate renamed duplicates or coincidence.

### 4. duplicates_summary.txt

Human-readable summary with key statistics and top space wasters.

**Example:**
```
======================================================================
ComfyUI Models Duplicate Detection Report
======================================================================

INVENTORY SUMMARY
----------------------------------------------------------------------
Total models scanned:             104
Total storage used:               493.05 GB

DUPLICATE ANALYSIS
----------------------------------------------------------------------
Filename duplicates:              5 unique names
Size duplicates:                  15 unique sizes
Exact duplicates (name + size):   4 files

Exact duplicate instances:        8
Extra copies:                     4
Wasted space:                     19.29 GB
Potential savings:                3.9% of total storage

======================================================================
TOP SPACE WASTERS (Exact Duplicates)
======================================================================

1. z-image-turbo-fp8-aio.safetensors
   Size: 9.63 GB  |  Copies: 2  |  Wasted: 9.63 GB
   Locations:
     • C:\ComfyUI_Models\models\checkpoints
     • C:\ComfyUI_Models\models\checkpoints\Z-image

2. t5xxl_fp16.safetensors
   Size: 9.12 GB  |  Copies: 2  |  Wasted: 9.12 GB
   Locations:
     • C:\ComfyUI_Models\models\text_encoders\FLUX_Fill
     • C:\ComfyUI_Models\models\text_encoders\SD3
```

## Understanding Duplicate Types

### ✅ Exact Duplicates (High Confidence)
- **Same filename AND same size**
- Safe to delete one copy
- Most reliable indicator of true duplicates
- Script calculates exact wasted space

### ⚠️ Filename Duplicates (Review Needed)
- **Same filename but different sizes**
- Likely different versions of the same model
- Keep the version you need, delete others
- Check file dates to identify newest/oldest

### 🔍 Size Duplicates (Investigate)
- **Same size but different names**
- Could be renamed duplicates
- Could be coincidence (same size ≠ same file)
- Cross-reference with actual file content if critical

## Use Cases

### Quick Cleanup - Find Exact Duplicates

```bash
python find_duplicates.py models_inventory.csv -t exact -o cleanup
# Review cleanup/exact_duplicates.csv
# Delete extra copies to save space
```

### Version Management - Find Filename Duplicates

```bash
python find_duplicates.py models_inventory.csv -t name -o versions
# Review versions/duplicates_by_name.csv
# Keep newest or preferred version
```

### Space Audit - Find All Duplicates

```bash
python find_duplicates.py models_inventory.csv -o audit
# Review audit/duplicates_summary.txt for overview
# Check each report type for different cleanup opportunities
```

### Combined Analysis

```bash
# Find duplicates
python find_duplicates.py models_inventory.csv -o reports

# Cross-reference with usage
python cross_reference.py models_inventory.csv workflow_references.csv -o reports

# Safe cleanup strategy:
# 1. Delete exact duplicates (keep one copy)
# 2. Delete unused models from cross_reference report
# 3. Review filename duplicates and keep preferred version
```

## Cleanup Recommendations

### Priority 1: Exact Duplicates
1. Open `exact_duplicates.csv`
2. Sort by `size_gb` (largest first)
3. For each duplicate group:
   - Keep the copy in the most logical location
   - Delete the others
4. Verify with cross_reference tool that kept copy is used

### Priority 2: Unused Duplicates
1. Run cross_reference tool to find unused models
2. Cross-check with exact duplicates
3. Delete duplicates that are also unused
4. Maximum space savings with minimum risk

### Priority 3: Filename Duplicates
1. Open `duplicates_by_name.csv`
2. Compare file dates and sizes
3. Keep the newest or largest (usually most complete)
4. Test workflows before deleting older versions

## Safety Tips

1. **Backup First** - Always backup before deleting models
2. **Cross-Reference** - Use with cross_reference.py to avoid breaking workflows
3. **Test After Cleanup** - Run workflows to ensure they still work
4. **Keep One Copy** - Never delete all copies of an exact duplicate
5. **Check Dates** - Newer files are usually (but not always) preferred

## Example Session

```bash
$ python find_duplicates.py models_inventory.csv -o reports

======================================================================
ComfyUI Models Duplicate Detection
======================================================================

Models inventory:  models_inventory.csv
Output directory:  reports
Detection type:    all

----------------------------------------------------------------------

Loading models inventory...
  Loaded 104 models
  Total size: 493.05 GB

Analyzing duplicates...
  Found 5 filename duplicates
  Found 15 size duplicates
  Found 4 exact duplicates (same name AND size)

Generating reports...

🎯 Exact duplicates report: reports/exact_duplicates.csv
   Found 4 files with exact duplicates (same name AND size)
   Total instances: 8 (4 extra copies)
   Wasted space: 19.29 GB

======================================================================
Analysis Complete!
======================================================================

💡 You have 4 extra copies of 4 files
   Delete duplicates to save 19.29 GB of disk space!

All reports saved to: reports
```

## Interpreting Results

### Good Signs
- Low percentage of exact duplicates
- Few filename duplicates (suggests good organization)
- Small wasted space percentage

### Warning Signs
- High exact duplicate count (>10% of models)
- Large wasted space (>20% of total storage)
- Many filename duplicates with very different sizes

### Common Patterns

**Pattern 1: Accidental Copies**
```
Same file in:
  C:\Models\checkpoints\model.safetensors
  C:\Models\checkpoints\backup\model.safetensors
Action: Delete backup copy
```

**Pattern 2: Multiple Install Locations**
```
Same file in:
  C:\ComfyUI\models\checkpoints\model.safetensors
  C:\ComfyUI_Models\models\checkpoints\model.safetensors
Action: Consolidate to one location, update ComfyUI paths
```

**Pattern 3: Version Hoarding**
```
model_v1.safetensors (6.46 GB)
model_v2.safetensors (6.46 GB)
model_v3.safetensors (7.23 GB)
Action: Keep v3, delete v1 and v2 if not needed
```

## Troubleshooting

**No duplicates found but I know there are some:**
- Verify models_inventory.csv has size information
- Check that filenames are exactly the same (case-insensitive matching is used)
- Different file dates don't affect matching

**Too many size duplicates:**
- Size duplicates can be coincidental
- Focus on exact duplicates for safe cleanup
- Use -t exact to see only confirmed duplicates

**Different sizes for same filename:**
- These are different versions
- Check file dates to identify which is newer
- Consider keeping both if actively used in different workflows

## Integration with Other Tools

Works with:
- **scan_models.py** - Creates the inventory (required input)
- **cross_reference.py** - Identifies which duplicates are used/unused
- **scan_safetensors.py** - Shows which duplicates are referenced in workflows

Complete workflow:
```bash
# 1. Create inventory
python scan_models.py models_lst.txt -o inventory.csv

# 2. Find duplicates
python find_duplicates.py inventory.csv -o dup_reports

# 3. Check usage
python scan_safetensors.py C:\workflows -o refs.csv
python cross_reference.py inventory.csv refs.csv -o usage_reports

# 4. Safe cleanup:
#    - Delete exact duplicates from dup_reports/exact_duplicates.csv
#    - Prioritize unused duplicates from usage_reports/unused_models.csv
```
