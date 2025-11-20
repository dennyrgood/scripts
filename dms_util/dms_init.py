#!/usr/bin/env python3
"""
dms_init.py - Initialize a new Doc/ directory with DMS

Creates:
  - Doc/ directory (if needed)
  - .dms_state.json (empty state file)
  - index.html (empty initial HTML)

Usage:
  python3 dms_init.py --doc Doc
"""
import argparse
import json
import sys
from pathlib import Path
from datetime import datetime

def init_dms(doc_dir: Path) -> int:
    """Initialize DMS for a new Doc/ directory"""
    
    print("=== Initializing DMS ===\n")
    
    # Create Doc/ if needed
    if not doc_dir.exists():
        doc_dir.mkdir(parents=True)
        print(f"✓ Created {doc_dir}")
    else:
        print(f"✓ Using existing {doc_dir}")
    
    # Create .dms_state.json
    state_path = doc_dir / ".dms_state.json"
    
    initial_state = {
        "metadata": {
            "created": datetime.now().isoformat(),
            "last_scan": None,
            "last_apply": None
        },
        "categories": [
            "Guides",
            "Workflows",
            "Scripts",
            "Models",
            "QuickRefs",
            "Junk"
        ],
        "documents": {}
    }
    
    state_path.write_text(json.dumps(initial_state, indent=2), encoding='utf-8')
    print(f"✓ Created {state_path}")
    
    # Generate initial index.html
    index_path = doc_dir / "index.html"
    
    # Call dms_render to generate from empty state
    import subprocess
    from pathlib import Path as PathlibPath
    
    scripts_dir = PathlibPath.home() / "Documents/MyWebsiteGIT/Scripts"
    render_script = scripts_dir / "dms_util" / "dms_render.py"
    
    if render_script.exists():
        result = subprocess.run(
            [sys.executable, str(render_script),
             "--doc", str(doc_dir),
             "--index", str(index_path)],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            print(f"✓ Created {index_path}")
        else:
            print(f"WARNING: Could not render index.html: {result.stderr}", file=sys.stderr)
    else:
        print(f"WARNING: dms_render.py not found, skipping index.html generation", file=sys.stderr)
    
    print(f"\n✓ DMS initialized!")
    print(f"\nNext steps:")
    print(f"  1. Add documents to {doc_dir}/")
    print(f"  2. Run: dms scan")
    print(f"  3. Run: dms summarize")
    print(f"  4. Run: dms review")
    print(f"  5. Run: dms apply")
    
    return 0

def main():
    parser = argparse.ArgumentParser(description="Initialize DMS for a Doc/ directory")
    parser.add_argument("--doc", default="Doc", help="Doc directory to create/use")
    args = parser.parse_args()
    
    doc_dir = Path(args.doc)
    
    return init_dms(doc_dir)

if __name__ == "__main__":
    exit(main())
