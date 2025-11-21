#!/usr/bin/env python3
"""
dms_categories.py - Manage categories in .dms_state.json

Operations:
  list              - Show all categories and file counts
  add <name>        - Add new category
  rename <old> <new> - Rename category (updates all docs)
  move <file> <cat> - Move file to category
  delete <name>     - Delete category (moves docs to Junk)

Usage:
  python3 dms_categories.py --doc Doc list
  python3 dms_categories.py --doc Doc add "NewCategory"
  python3 dms_categories.py --doc Doc move "./myfile.txt" "Scripts"
  python3 dms_categories.py --doc Doc rename "OldName" "NewName"
  python3 dms_categories.py --doc Doc delete "OldName"
"""
import argparse
import sys
import json
from pathlib import Path

def load_state(state_path: Path) -> dict:
    """Load .dms_state.json"""
    if not state_path.exists():
        print(f"ERROR: {state_path} not found")
        sys.exit(1)
    return json.loads(state_path.read_text(encoding='utf-8'))

def save_state(state_path: Path, state: dict) -> None:
    """Save .dms_state.json"""
    state_path.write_text(json.dumps(state, indent=2), encoding='utf-8')

def cmd_list(state: dict, state_path: Path) -> int:
    """List all categories and file counts"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    print("\n=== CATEGORIES ===\n")
    
    for cat in categories:
        count = sum(1 for d in documents.values() if d.get('category') == cat)
        print(f"  {cat}: {count} file(s)")
    
    # Show orphaned files (using categories not in list)
    used_cats = set(d.get('category') for d in documents.values())
    orphaned = used_cats - set(categories)
    if orphaned:
        print("\n  ⚠ Orphaned (not in category list):")
        for cat in orphaned:
            count = sum(1 for d in documents.values() if d.get('category') == cat)
            print(f"    {cat}: {count} file(s)")
    
    print()
    return 0

def cmd_add(state: dict, state_path: Path, name: str) -> int:
    """Add new category"""
    categories = state.get('categories', [])
    
    if name in categories:
        print(f"✗ Category already exists: {name}")
        return 1
    
    categories.append(name)
    save_state(state_path, state)
    print(f"✓ Added category: {name}")
    return 0

def cmd_move(state: dict, state_path: Path, file_path: str, category: str) -> int:
    """Move file to category"""
    documents = state.get('documents', {})
    categories = state.get('categories', [])
    
    if file_path not in documents:
        print(f"✗ File not found: {file_path}")
        return 1
    
    if category not in categories:
        print(f"✗ Category not found: {category}")
        print(f"   Available: {', '.join(categories)}")
        return 1
    
    old_cat = documents[file_path].get('category', 'Unknown')
    documents[file_path]['category'] = category
    save_state(state_path, state)
    
    print(f"✓ Moved: {file_path}")
    print(f"  {old_cat} → {category}")
    return 0

def cmd_rename(state: dict, state_path: Path, old_name: str, new_name: str) -> int:
    """Rename category (updates all docs using it)"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    if old_name not in categories:
        print(f"✗ Category not found: {old_name}")
        return 1
    
    if new_name in categories:
        print(f"✗ Category already exists: {new_name}")
        return 1
    
    # Update categories list
    idx = categories.index(old_name)
    categories[idx] = new_name
    
    # Update all documents using this category
    updated = 0
    for doc_data in documents.values():
        if doc_data.get('category') == old_name:
            doc_data['category'] = new_name
            updated += 1
    
    save_state(state_path, state)
    
    print(f"✓ Renamed: {old_name} → {new_name}")
    print(f"  Updated {updated} document(s)")
    return 0

def cmd_delete(state: dict, state_path: Path, name: str) -> int:
    """Delete category (moves docs to Junk)"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    if name not in categories:
        print(f"✗ Category not found: {name}")
        return 1
    
    # Find all docs using this category
    moved = 0
    for doc_data in documents.values():
        if doc_data.get('category') == name:
            doc_data['category'] = 'Junk'
            moved += 1
    
    # Remove from categories
    categories.remove(name)
    
    save_state(state_path, state)
    
    print(f"✓ Deleted: {name}")
    print(f"  Moved {moved} document(s) to Junk")
    return 0

def main():
    parser = argparse.ArgumentParser(description="Manage DMS categories")
    parser.add_argument("--doc", default="Doc", help="Doc directory")
    subparsers = parser.add_subparsers(dest="command", help="Command")
    
    subparsers.add_parser("list", help="List all categories")
    subparsers.add_parser("add", help="Add category").add_argument("name")
    
    mv = subparsers.add_parser("move", help="Move file to category")
    mv.add_argument("file", help="File path (e.g., './myfile.txt')")
    mv.add_argument("category", help="Target category")
    
    rn = subparsers.add_parser("rename", help="Rename category")
    rn.add_argument("old", help="Old category name")
    rn.add_argument("new", help="New category name")
    
    subparsers.add_parser("delete", help="Delete category").add_argument("name")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 0
    
    doc_dir = Path(args.doc)
    state_path = doc_dir / ".dms_state.json"
    
    if not doc_dir.exists():
        print(f"ERROR: {doc_dir} not found")
        return 1
    
    state = load_state(state_path)
    
    if args.command == "list":
        return cmd_list(state, state_path)
    elif args.command == "add":
        return cmd_add(state, state_path, args.name)
    elif args.command == "move":
        return cmd_move(state, state_path, args.file, args.category)
    elif args.command == "rename":
        return cmd_rename(state, state_path, args.old, args.new)
    elif args.command == "delete":
        return cmd_delete(state, state_path, args.name)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
