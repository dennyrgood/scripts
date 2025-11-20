#!/usr/bin/env python3
"""
dms_review.py - Interactive approval of AI summaries

Reads: .dms_pending_summaries.json (from summarize step)
Outputs: .dms_pending_approved.json (ready for apply)

User can:
- Approve/reject summaries
- Edit summaries and categories
- Skip files
"""
import argparse
import sys
import json
from pathlib import Path


SCRIPTS_DIR = Path.home() / "Documents/MyWebsiteGIT/Scripts"

def load_pending_summaries(pending_path: Path) -> dict:
    """Load pending summaries from summarize step"""
    if not pending_path.exists():
        return {"summaries": []}
    return json.loads(pending_path.read_text(encoding='utf-8'))

def approve_summary(summary_info: dict) -> bool:
    """Interactive approval of a single summary"""
    file_path = summary_info['file']['path']
    summary = summary_info['summary']
    category = summary_info['category']
    
    print(f"\n{'='*70}")
    print(f"File: {file_path}")
    print(f"Summary: {summary}")
    print(f"Category: {category}")
    print(f"{'='*70}")
    
    while True:
        # Show that approve is the default by indicating it in the prompt
        choice = input("\n[a]pprove (default), [e]dit, [c]ategory, [s]kip, [q]uit? > ").strip().lower()
        # Treat an empty input (simple Enter) as approve
        if choice == '':
            choice = 'a'
        
        if choice == 'a':
            return True
        elif choice == 'e':
            new_summary = input("\nEdit summary:\n> ").strip()
            if new_summary:
                summary_info['summary'] = new_summary
            return True
        elif choice == 'c':
            print("\nCategories: Guides, Workflows, Scripts, Models, QuickRefs, Junk")
            new_cat = input("New category: ").strip()
            if new_cat:
                summary_info['category'] = new_cat
            return True
        elif choice == 's':
            return False  # Skip this one
        elif choice == 'q':
            return None  # Quit
        else:
            print("Invalid choice")

def main():
    parser = argparse.ArgumentParser(description="Interactive review of summaries")
    parser.add_argument("--doc", default="Doc", help="Doc directory")
    parser.add_argument("--all", action="store_true", help="Auto-approve all without review")
    args = parser.parse_args()
    
    doc_dir = Path(args.doc)
    pending_path = doc_dir / ".dms_pending_summaries.json"
    approved_path = doc_dir / ".dms_pending_approved.json"
    
    if not doc_dir.exists():
        print(f"ERROR: {doc_dir} not found")
        return 1
    
    # Load pending summaries
    pending_data = load_pending_summaries(pending_path)
    summaries = pending_data.get('summaries', [])
    
    if not summaries:
        print("No pending summaries to review.")
        return 0
    
    print(f"==> Reviewing {len(summaries)} summary/summaries...\n")
    
    approved = []
    skipped = 0
    
    if args.all:
        # Auto-approve all
        approved = summaries
        print(f"✓ Auto-approved all {len(summaries)} summaries")
    else:
        # Interactive review
        for i, summary_info in enumerate(summaries, 1):
            print(f"\n[{i}/{len(summaries)}]")
            
            result = approve_summary(summary_info)
            
            if result is None:
                # User quit
                print("\nReview interrupted.")
                break
            elif result:
                approved.append(summary_info)
            else:
                skipped += 1
        
        print(f"\n{'='*70}")
        print(f"Review complete: {len(approved)} approved, {skipped} skipped")
    
    if not approved:
        print("No summaries to apply.")
        return 0
    
    # Save approved summaries
    approved_data = {
        "timestamp": pending_data.get('timestamp'),
        "summaries": approved
    }
    
    approved_path.write_text(json.dumps(approved_data, indent=2), encoding='utf-8')
    
    print(f"✓ Saved {len(approved)} approved summary/summaries to {approved_path}")
    print(f"\nNext step:")
    print(f"  Run: dms apply")
    
    # Cleanup pending file
    if pending_path.exists():
        pending_path.unlink()
    
    return 0

if __name__ == "__main__":
    exit(main())
