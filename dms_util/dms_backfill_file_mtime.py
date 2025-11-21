#!/usr/bin/env python3
"""
dms_backfill_file_mtime.py - One-time backfill of file_mtime for existing documents

Reads .dms_state.json and adds file_mtime to any documents that are missing it.
Only runs once - after this, all new files will have file_mtime from scan/apply.

Usage:
  python3 dms_util/dms_backfill_file_mtime.py --doc Doc
"""
import argparse
import sys
import json
from pathlib import Path
from datetime import datetime

def get_file_mtime_iso(path: Path) -> str:
    """Get file modification time in ISO 8601 format"""
    mtime = path.stat().st_mtime
    return datetime.fromtimestamp(mtime).isoformat()

def backfill_mtime(doc_dir: Path, state_path: Path) -> int:
    """Add file_mtime to existing documents in state"""
    
    if not state_path.exists():
        print(f"ERROR: {state_path} not found")
        return 1
    
    print("==> Backfilling file_mtime for existing documents...\n")
    
    # Load state
    state = json.loads(state_path.read_text(encoding='utf-8'))
    documents = state.get('documents', {})
    
    updated = 0
    skipped = 0
    missing = 0
    
    for file_path, doc_data in documents.items():
        # Skip if already has file_mtime
        if doc_data.get('file_mtime'):
            skipped += 1
            continue
        
        # Try to get mtime from actual file
        full_path = doc_dir / file_path.lstrip('./')
        
        if not full_path.exists():
            print(f"  ⚠ File not found: {file_path}")
            missing += 1
            continue
        
        try:
            mtime = get_file_mtime_iso(full_path)
            doc_data['file_mtime'] = mtime
            print(f"  ✓ Added: {file_path} → {mtime}")
            updated += 1
        except Exception as e:
            print(f"  ✗ Error: {file_path} - {e}")
            continue
    
    # Save updated state
    state_path.write_text(json.dumps(state, indent=2), encoding='utf-8')
    
    print(f"\n=== BACKFILL COMPLETE ===")
    print(f"✓ Updated: {updated}")
    print(f"⊘ Skipped (already had mtime): {skipped}")
    print(f"✗ Missing: {missing}")
    print(f"\nState saved: {state_path}")
    
    return 0

def main():
    parser = argparse.ArgumentParser(
        description="Backfill file_mtime for existing documents in .dms_state.json"
    )
    parser.add_argument("--doc", default="Doc", help="Doc directory")
    args = parser.parse_args()
    
    doc_dir = Path(args.doc)
    state_path = doc_dir / ".dms_state.json"
    
    if not doc_dir.exists():
        print(f"ERROR: {doc_dir} not found")
        return 1
    
    return backfill_mtime(doc_dir, state_path)

if __name__ == "__main__":
    sys.exit(main())
