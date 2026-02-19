# ComfyUI Models Directory Scanner

This script parses a Windows directory listing file (output from `dir /s` command) and extracts all `.safetensors` model files into a CSV inventory.

## Purpose

Create an inventory of all safetensor model files from a ComfyUI models directory listing, including:
- Filename
- Full directory path
- File date/time
- Safetensor filename (same as filename in this context)

## Creating the Input File

On Windows, run this command in your ComfyUI models directory:

```cmd
dir /s > models_lst.txt
```

Or for a specific subdirectory:

```cmd
cd C:\ComfyUI_Models\models
dir /s > models_lst.txt
```

## Requirements

Python 3.6 or higher (no additional packages needed)

## Usage

### Basic Usage

```bash
python scan_models.py models_lst.txt
```

This creates `models_inventory.csv` in the current directory.

### Specify Output File

```bash
python scan_models.py models_lst.txt -o my_models.csv
```

### Windows Example

```cmd
python scan_models.py "C:\ComfyUI\models_lst.txt" -o "C:\reports\models.csv"
```

## Output Format

The CSV file contains the following columns:

| Column | Description |
|--------|-------------|
| `filename` | Name of the .safetensors file |
| `directory` | Full Windows path to the directory containing the file |
| `file_date` | File modification date and time (MM/DD/YYYY HH:MM AM/PM) |
| `size_bytes` | File size in bytes (exact) |
| `size_mb` | File size in megabytes (rounded to 2 decimal places) |
| `size_gb` | File size in gigabytes (rounded to 2 decimal places) |
| `safetensor_file` | Same as filename (for compatibility with workflow scanner output) |

### Example Output

```csv
filename,directory,file_date,size_bytes,size_mb,size_gb,safetensor_file
flux1-dev-fp8.safetensors,C:\ComfyUI_Models\models\checkpoints\FLUX,01/12/2026 02:58 PM,17246524772,16447.57,16.06,flux1-dev-fp8.safetensors
dreamshaper_8.safetensors,C:\ComfyUI_Models\models\checkpoints\SD1.5,01/02/2026 05:34 PM,2132625894,2033.83,1.99,dreamshaper_8.safetensors
sd3_medium.safetensors,C:\ComfyUI_Models\models\checkpoints\SD3,01/12/2026 09:31 PM,4337667306,4136.72,4.04,sd3_medium.safetensors
```

The script also displays total size summary:
```
Wrote 104 safetensor files to models_inventory.csv
Total size: 493.1 GB (529,466,477,004 bytes)
```

## How It Works

1. **Parse Input**: Reads the Windows directory listing file line by line
2. **Extract Directory**: Identifies "Directory of" headers to track current path
3. **Match Files**: Uses regex to extract file information (date, time, size, filename)
4. **Filter**: Only includes files with `.safetensors` extension
5. **Generate CSV**: Creates a CSV with all found safetensor files

## Use Cases

### Model Inventory
Track all models installed in your ComfyUI setup:
```bash
python scan_models.py models_lst.txt -o inventory.csv
```

### Storage Analysis
- Identify largest models taking up disk space
- Sort by size_gb column in Excel to find space hogs
- Calculate total storage used by model type (checkpoints, LoRAs, etc.)
- Plan which models to archive or delete based on size

### Cross-Reference with Workflows
Combine with the workflow scanner to see which models are actually being used:
1. Run `scan_models.py` to get all available models with sizes
2. Run `scan_safetensors.py` to get models referenced in workflows
3. Compare the two CSV files to find unused models
4. Sort by size to prioritize removing large unused models

### Duplicate Detection
Import the CSV into Excel or a database to find:
- Duplicate filenames in different directories
- Multiple versions of the same model
- Large files that might be duplicates
- Similar-sized files that could be duplicates

### Backup Planning
Use the CSV to:
- Identify which models to backup based on size and usage
- Calculate total storage requirements (see total in output)
- Prioritize backing up smaller, frequently-used models first
- Plan cloud storage needs based on total GB

## Notes

- The script only processes `.safetensors` files (not .ckpt, .pt, .bin, etc.)
- Preserves the full Windows path including subdirectories
- Handles paths with spaces and special characters
- Case-insensitive matching for `.safetensors` extension

## Example Workflow

```bash
# 1. Generate directory listing on Windows
cd C:\ComfyUI_Models\models
dir /s > models_lst.txt

# 2. Create model inventory
python scan_models.py models_lst.txt -o available_models.csv

# 3. Scan workflows for model usage
python scan_safetensors.py C:\ComfyUI\output -o used_models.csv

# 4. Compare the two CSVs to find unused models
```

## Troubleshooting

**No files found:**
- Ensure the input file is from `dir /s` command
- Verify the file contains `.safetensors` files
- Check that the file is readable and properly formatted

**Encoding errors:**
- The script uses UTF-8 with error replacement
- If you have unusual characters, the CSV will still be generated

**Wrong dates/paths:**
- Ensure the directory listing is from Windows `dir /s` command
- Linux `ls -R` output uses a different format and won't work
