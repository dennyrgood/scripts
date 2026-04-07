#!/bin/bash
# =============================================================
#  comfy_fleet.sh
#  Wrapper for comfy_fleet.py
#  Place in ~/repos/scripts/comfyui/ alongside comfy_fleet.py
#
#  Usage:
#    ./comfy_fleet.sh              # uses fleet_config.json in comfy-reports
#    ./comfy_fleet.sh --year 2025  # override year filter
# =============================================================

REPORTS_DIR="$HOME/OneDrive/DropBoxReplacement/MathesDropBox/0ComfyUI/Work/comfy-reports"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "============================================="
echo "  ComfyUI Fleet Analysis"
echo "  Reports : $REPORTS_DIR"
echo "============================================="
echo ""

cd "$REPORTS_DIR" || { echo "ERROR: Could not cd to $REPORTS_DIR"; exit 1; }

python3 "$SCRIPT_DIR/comfy_fleet.py" "$@"
