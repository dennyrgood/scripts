#!/usr/bin/env python3
"""
dms_scan.py - Scan Doc/ directory for new or changed files

Compares current filesystem state against .dms_state.json
Identifies:
  - New files (not in state)
  - Changed files (hash mismatch)
  - Missing files (in state but not on disk)

Outputs a scan report (no state changes - just detection).
"""
import argparse
import sys
import json
import hashlib
from pathlib import Path
from datetime import datetime

def compute_file_hash(path: Path) -> str:
    """Compute SHA-256 hash of file contents"""
    sha = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(8192):
            sha.update(chunk)
    return f"sha256:{sha.hexdigest()}"

def load_state(state_path: Path) -> dict:
    """Load .dms_state.json"""
    if not state_path.exists():
        return {
            "metadata": {"last_scan": None},
            "categories": [],
            "documents": {}
        }
    
    try:
        return json.loads(state_path.read_text(encoding='utf-8'))
    except Exception as e:
        print(f"WARNING: Error loading state: {e}", file=sys.stderr)
        return {
            "metadata": {"last_scan": None},
            "categories": [],
            "documents": {}
        }

def scan_directory(doc_dir: Path, state: dict) -> tuple:
    """Scan Doc/ directory and detect changes
    
    Handles file pairs:
    - Original file (image, PDF, etc) + readable version in md_outputs/
    - Only the readable version is tracked as a document
    - Original file is linked but ignored during scan
    """
    
    new_files = []
    changed_files = []
    missing_files = []
    
    state_docs = state.get("documents", {})
    
    # Find files on disk
    disk_files = {}
    for file_path in doc_dir.rglob("*"):
        if file_path.is_file():
            # Skip hidden files and common non-doc files
            if file_path.name.startswith('.'):
                continue
            # Relative path from doc_dir
            rel_path = f"./{file_path.relative_to(doc_dir)}"
            disk_files[rel_path] = file_path
    
    # Find which files have readable versions in md_outputs
    # Maps original file -> readable file
    readable_versions = {}
    for rel_path in disk_files.keys():
        if './md_outputs/' in rel_path:
            # This is a readable version
            # Find its corresponding original
            filename = Path(rel_path).stem  # Remove .txt
            
            # Look for matching original in root
            for orig_path in disk_files.keys():
                if './md_outputs/' not in orig_path:  # In root
                    if Path(orig_path).stem == filename:
                        readable_versions[orig_path] = rel_path
                        break
    
    # Check for new and changed files
    for rel_path, file_path in disk_files.items():
        # Skip original files that have readable versions
        if rel_path in readable_versions:
            continue
        
        # Skip readable versions in md_outputs if they're paired with originals
        if './md_outputs/' in rel_path:
            # Check if this is a readable version of an original
            is_paired = False
            for orig, readable in readable_versions.items():
                if readable == rel_path:
                    is_paired = True
                    break
            
            if is_paired:
                # Process the original file instead, which will include the readable link
                continue
        
        file_hash = compute_file_hash(file_path)
        
        if rel_path not in state_docs:
            # New file
            file_info = {
                "path": rel_path,
                "hash": file_hash,
                "size": file_path.stat().st_size
            }
            
            # If this file has a readable version, link it
            if rel_path in readable_versions:
                file_info["readable_version"] = readable_versions[rel_path]
            
            new_files.append(file_info)
        else:
            # Check if changed
            if state_docs[rel_path].get("hash") != file_hash:
                changed_files.append({
                    "path": rel_path,
                    "old_hash": state_docs[rel_path].get("hash"),
                    "new_hash": file_hash
                })
    
    # Check for missing files (in state but not on disk)
    for rel_path, doc_data in state_docs.items():
        if rel_path not in disk_files:
            missing_files.append({
                "path": rel_path,
                "was_category": doc_data.get("category", "Unknown")
            })
    
    return new_files, changed_files, missing_files

def print_report(new_files, changed_files, missing_files, status_only=False):
    """Print scan report"""
    
    print(f"\n=== DMS SCAN REPORT ===\n")
    print(f"New files: {len(new_files)}")
    if new_files and not status_only:
        for f in new_files[:10]:
            print(f"  + {f['path']}")
        if len(new_files) > 10:
            print(f"  ... and {len(new_files) - 10} more")
    
    print(f"\nChanged files: {len(changed_files)}")
    if changed_files and not status_only:
        for f in changed_files[:10]:
            print(f"  ~ {f['path']}")
        if len(changed_files) > 10:
            print(f"  ... and {len(changed_files) - 10} more")
    
    print(f"\nMissing files: {len(missing_files)}")
    if missing_files and not status_only:
        for f in missing_files[:10]:
            print(f"  - {f['path']} (was {f['was_category']})")
        if len(missing_files) > 10:
            print(f"  ... and {len(missing_files) - 10} more")
    
    total = len(new_files) + len(changed_files) + len(missing_files)
    print(f"\nTotal changes: {total}")
    
    if total == 0:
        print("✓ No changes detected. Index is up to date.")
    
    return total

def main():
    parser = argparse.ArgumentParser(description="Scan Doc/ directory for changes")
    parser.add_argument("--doc", default="Doc", help="Doc directory")
    parser.add_argument("--status-only", action="store_true", help="Just show status, don't save")
    args = parser.parse_args()
    
    doc_dir = Path(args.doc)
    state_path = doc_dir / ".dms_state.json"
    
    if not doc_dir.exists():
        print(f"ERROR: {doc_dir} not found")
        return 1
    
    # Load state
    state = load_state(state_path)
    
    # Scan directory
    new_files, changed_files, missing_files = scan_directory(doc_dir, state)
    
    # Print report
    total = print_report(new_files, changed_files, missing_files, args.status_only)
    
    if total == 0:
        return 0
    
    if args.status_only:
        return 0
    
    # Save scan results for next step
    # This is read by summarize/review
    scan_result = {
        "timestamp": datetime.now().isoformat(),
        "new_files": new_files,
        "changed_files": changed_files,
        "missing_files": missing_files
    }
    
    scan_file = doc_dir / ".dms_scan.json"
    scan_file.write_text(json.dumps(scan_result, indent=2))
    
    print(f"\n✓ Scan results saved to {scan_file}")
    print(f"\nNext steps:")
    print(f"  1. Review the changes above")
    print(f"  2. Run: dms summarize (to generate summaries for new files)")
    print(f"  3. Or run: dms cleanup (to remove missing files from state)")
    
    return 0

if __name__ == "__main__":
    exit(main())
