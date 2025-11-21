#!/usr/bin/env python3
"""
dms_categories_interactive.py - Advanced interactive category management

Full interactive menu for managing document categories:
- List all categories with file counts
- Add new categories
- Move files between categories (with preview/search)
- Rename categories
- Delete categories

Usage:
  dms_categories_interactive --doc Doc        # Interactive menu (default)

Non-interactive (command line):
  dms_categories_interactive --doc Doc list
  dms_categories_interactive --doc Doc add "NewCategory"
  dms_categories_interactive --doc Doc move "./file" "Category"
"""
import argparse
import sys
import json
from pathlib import Path

def load_state(state_path: Path) -> dict:
    """Load .dms_state.json"""
    if not state_path.exists():
        print(f"ERROR: {state_path} not found")
        return None
    
    try:
        return json.loads(state_path.read_text(encoding='utf-8'))
    except Exception as e:
        print(f"ERROR: Failed to load state: {e}", file=sys.stderr)
        return None

def save_state(state_path: Path, state: dict) -> None:
    """Save .dms_state.json"""
    state_path.write_text(json.dumps(state, indent=2), encoding='utf-8')

def list_categories(state: dict):
    """List all categories with file counts and files"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    if not categories:
        print("No categories defined.")
        return
    
    print(f"\n{'='*70}")
    print(f"CATEGORIES ({len(categories)} total)")
    print('='*70)
    
    for cat in categories:
        docs_in_cat = [d for d in documents.values() if d.get('category') == cat]
        print(f"\n📁 {cat}: {len(docs_in_cat)} file(s)")
        
        if docs_in_cat:
            for doc_info in sorted(docs_in_cat, key=lambda x: x.get('title', ''))[:5]:
                title = doc_info.get('title', 'Untitled')
                print(f"   • {title}")
            
            if len(docs_in_cat) > 5:
                print(f"   ... and {len(docs_in_cat) - 5} more")
    
    print()

def list_files_for_category(state: dict):
    """Show files in a category with options to move one or multiple"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    print("\nSelect category to view files:")
    for i, cat in enumerate(categories, 1):
        count = sum(1 for d in documents.values() if d.get('category') == cat)
        print(f"  {i}. {cat} ({count} files)")
    
    try:
        choice = int(input("\nEnter number: ").strip())
        if 1 <= choice <= len(categories):
            selected_cat = categories[choice - 1]
            docs_in_cat = [(p, d) for p, d in documents.items() if d.get('category') == selected_cat]
            
            if not docs_in_cat:
                print(f"\nNo files in '{selected_cat}'")
                return
            
            print(f"\n{'='*70}")
            print(f"Files in '{selected_cat}' ({len(docs_in_cat)} total)")
            print('='*70)
            
            for i, (path, doc) in enumerate(sorted(docs_in_cat), 1):
                title = doc.get('title', path)
                summary = doc.get('summary', '')[:50]
                print(f"  {i:2d}. {title}")
                print(f"      {summary}...")
            
            # Ask what user wants to do
            print("\nOptions:")
            print("  1. Move single file")
            print("  2. Move multiple files by pattern")
            print("  3. Move all files in this category")
            print("  4. Back to menu")
            
            action = input("\nSelect option (1-4): ").strip()
            
            if action == "1":
                # Single file
                try:
                    file_num = int(input(f"\nEnter file number (1-{len(docs_in_cat)}): ").strip())
                    if 1 <= file_num <= len(docs_in_cat):
                        file_path = sorted(docs_in_cat)[file_num - 1][0]
                        return move_file_to_category(documents, categories, file_path, selected_cat)
                except ValueError:
                    print("Invalid input")
            
            elif action == "2":
                # Multiple files by selection (like delete-entry)
                print(f"\nSelect files to move (enter numbers separated by comma, e.g., 1,3,5):")
                print("Or 'all' to move all, or 'none' to cancel\n")
                
                # Show numbered list with checkboxes
                for i, (path, doc) in enumerate(sorted(docs_in_cat), 1):
                    title = doc.get('title', path)
                    print(f"  [ ] {i}. {title}")
                
                selection = input("\nEnter selection: ").strip().lower()
                
                if selection == 'none' or selection == '':
                    return False
                
                if selection == 'all':
                    matching = [p for p, d in docs_in_cat]
                else:
                    # Parse comma-separated numbers
                    try:
                        indices = [int(x.strip()) - 1 for x in selection.split(',')]
                        sorted_docs = sorted(docs_in_cat)
                        matching = [sorted_docs[i][0] for i in indices if 0 <= i < len(sorted_docs)]
                    except ValueError:
                        print("Invalid selection format")
                        return False
                
                if not matching:
                    print("No files selected")
                    return False
                
                print(f"\nSelected {len(matching)} file(s):")
                for p in matching:
                    print(f"  • {documents[p].get('title', p)}")
                
                confirm = input(f"\nMove all {len(matching)} files to different category? [y/N]: ").strip().lower()
                if confirm == 'y':
                    print("\nSelect target category:")
                    for i, cat in enumerate(categories, 1):
                        marker = " ✓" if cat == selected_cat else ""
                        print(f"  {i}. {cat}{marker}")
                    
                    try:
                        target_num = int(input("\nEnter number: ").strip())
                        if 1 <= target_num <= len(categories):
                            target_cat = categories[target_num - 1]
                            moved = 0
                            for file_path in matching:
                                old_cat = documents[file_path].get('category')
                                documents[file_path]['category'] = target_cat
                                moved += 1
                            
                            print(f"\n✓ Moved {moved} file(s)")
                            print(f"  {selected_cat} → {target_cat}")
                            return True
                    except ValueError:
                        print("Invalid input")

            
            elif action == "3":
                # All files
                print(f"\n⚠ Move all {len(docs_in_cat)} files from '{selected_cat}'?")
                
                print("\nSelect target category:")
                for i, cat in enumerate(categories, 1):
                    marker = " ✓" if cat == selected_cat else ""
                    print(f"  {i}. {cat}{marker}")
                
                try:
                    target_num = int(input("\nEnter number: ").strip())
                    if 1 <= target_num <= len(categories):
                        target_cat = categories[target_num - 1]
                        
                        if target_cat == selected_cat:
                            print("Files already in that category.")
                            return False
                        
                        confirm = input(f"\nMove all {len(docs_in_cat)} files to '{target_cat}'? [y/N]: ").strip().lower()
                        if confirm == 'y':
                            for file_path, _ in docs_in_cat:
                                documents[file_path]['category'] = target_cat
                            
                            print(f"\n✓ Moved {len(docs_in_cat)} file(s)")
                            print(f"  {selected_cat} → {target_cat}")
                            return True
                except ValueError:
                    print("Invalid input")
        else:
            print("Invalid choice")
    except ValueError:
        print("Invalid input")
    
    return False

def move_file_to_category(documents: dict, categories: list, file_path: str, source_cat: str) -> bool:
    """Move a single file to target category"""
    print("\nSelect target category:")
    for i, cat in enumerate(categories, 1):
        marker = " ✓" if cat == source_cat else ""
        print(f"  {i}. {cat}{marker}")
    
    try:
        target_num = int(input("\nEnter number: ").strip())
        if 1 <= target_num <= len(categories):
            target_cat = categories[target_num - 1]
            old_cat = documents[file_path].get('category')
            documents[file_path]['category'] = target_cat
            print(f"\n✓ Moved: {documents[file_path].get('title', file_path)}")
            print(f"  {old_cat} → {target_cat}")
            return True
    except ValueError:
        print("Invalid input")
    
    return False

def check_similar_names(name: str, categories: list) -> str:
    """Check for dangerously similar category names"""
    name_lower = name.lower()
    
    for existing in categories:
        existing_lower = existing.lower()
        
        # Check if one contains the other
        if name_lower in existing_lower or existing_lower in name_lower:
            # They share significant text
            if name_lower != existing_lower:  # But not identical
                return f"⚠ WARNING: Similar to existing category '{existing}'\n  This could confuse the AI when suggesting categories.\n  Consider a more distinct name."
    
    return None

def add_category(state: dict):
    """Add new category interactively"""
    categories = state.get('categories', [])
    
    print("\n" + "="*70)
    print("ADD NEW CATEGORY")
    print("="*70)
    print("\nExisting categories:")
    for cat in categories:
        print(f"  • {cat}")
    
    print("\n" + "-"*70)
    print("💡 NAMING TIPS:")
    print("-"*70)
    print("Avoid names too similar to existing ones - this can confuse the AI.")
    print("\nGood examples for archival/legacy categories:")
    print("  • Archived-Workflows")
    print("  • Legacy-Workflows")
    print("  • Old-Workflows")
    print("  • Workflows-Archive")
    print("\nBad examples (too similar):")
    print("  ✗ Workflow (similar to 'Workflows')")
    print("  ✗ Workflows - old (ambiguous)")
    print("="*70 + "\n")
    
    name = input("Enter new category name: ").strip()
    
    if not name:
        print("Cancelled.")
        return False
    
    if name in categories:
        print(f"✗ Category already exists: {name}")
        return False
    
    # Check for similar names
    warning = check_similar_names(name, categories)
    if warning:
        print(f"\n{warning}")
        confirm = input("\nAdd anyway? [y/N]: ").strip().lower()
        if confirm != 'y':
            print("Cancelled.")
            return False
    
    categories.append(name)
    print(f"✓ Added category: {name}")
    return True

def rename_category(state: dict):
    """Rename category interactively"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    print("\n" + "="*70)
    print("RENAME CATEGORY")
    print("="*70)
    
    print("\nSelect category to rename:")
    for i, cat in enumerate(categories, 1):
        count = sum(1 for d in documents.values() if d.get('category') == cat)
        print(f"  {i}. {cat} ({count} files)")
    
    try:
        choice = int(input("\nEnter number: ").strip())
        if 1 <= choice <= len(categories):
            old_name = categories[choice - 1]
            
            print("\n" + "-"*70)
            print("💡 NAMING TIPS:")
            print("-"*70)
            print("Avoid names too similar to existing ones - this can confuse the AI.")
            print("\nGood examples for archival/legacy categories:")
            print("  • Archived-Workflows")
            print("  • Legacy-Workflows")
            print("  • Old-Workflows")
            print("  • Workflows-Archive")
            print("\nBad examples (too similar):")
            print("  ✗ Workflow (similar to 'Workflows')")
            print("  ✗ Workflows - old (ambiguous)")
            print("="*70 + "\n")
            
            new_name = input(f"New name for '{old_name}': ").strip()
            
            if not new_name:
                print("Cancelled.")
                return False
            
            if new_name in categories:
                print(f"✗ Category already exists: {new_name}")
                return False
            
            # Check for similar names
            warning = check_similar_names(new_name, categories)
            if warning:
                print(f"\n{warning}")
                confirm = input("\nRename anyway? [y/N]: ").strip().lower()
                if confirm != 'y':
                    print("Cancelled.")
                    return False
            
            # Update categories list
            categories[choice - 1] = new_name
            
            # Update all documents
            updated = 0
            for doc_data in documents.values():
                if doc_data.get('category') == old_name:
                    doc_data['category'] = new_name
                    updated += 1
            
            print(f"\n✓ Renamed: {old_name} → {new_name}")
            print(f"  Updated {updated} file(s)")
            return True
        else:
            print("Invalid choice")
    except ValueError:
        print("Invalid input")
    
    return False

def delete_category(state: dict):
    """Delete category interactively"""
    categories = state.get('categories', [])
    documents = state.get('documents', {})
    
    print("\n" + "="*70)
    print("DELETE CATEGORY")
    print("="*70)
    
    print("\nSelect category to delete:")
    for i, cat in enumerate(categories, 1):
        count = sum(1 for d in documents.values() if d.get('category') == cat)
        print(f"  {i}. {cat} ({count} files)")
    
    try:
        choice = int(input("\nEnter number: ").strip())
        if 1 <= choice <= len(categories):
            name = categories[choice - 1]
            docs_in_cat = sum(1 for d in documents.values() if d.get('category') == name)
            
            print(f"\n⚠ WARNING: Deleting '{name}'")
            print(f"  {docs_in_cat} file(s) will be moved to Junk")
            
            confirm = input(f"\nAre you sure? [y/N]: ").strip().lower()
            if confirm == 'y':
                # Move files to Junk
                for doc_data in documents.values():
                    if doc_data.get('category') == name:
                        doc_data['category'] = 'Junk'
                
                # Remove category
                categories.remove(name)
                
                print(f"\n✓ Deleted: {name}")
                print(f"  Moved {docs_in_cat} file(s) to Junk")
                return True
            else:
                print("Cancelled.")
        else:
            print("Invalid choice")
    except ValueError:
        print("Invalid input")
    
    return False

def interactive_menu(state: dict, state_path: Path) -> int:
    """Interactive category management menu"""
    
    changed = False  # Track changes across all operations
    
    while True:
        print("\n" + "="*70)
        print(" "*20 + "CATEGORY MANAGER")
        print("="*70)
        print("\nOptions:")
        print("  1. List all categories")
        print("  2. View files in category")
        print("  3. Add new category")
        print("  4. Rename category")
        print("  5. Delete category")
        print("  6. Save and exit")
        print("  7. Exit without saving")
        
        choice = input("\nEnter choice (1-7): ").strip()
        
        if choice == "1":
            list_categories(state)
            input("Press Enter to continue...")
        
        elif choice == "2":
            if list_files_for_category(state):
                changed = True
                input("\nPress Enter to continue...")
        
        elif choice == "3":
            if add_category(state):
                changed = True
            input("\nPress Enter to continue...")
        
        elif choice == "4":
            if rename_category(state):
                changed = True
            input("\nPress Enter to continue...")
        
        elif choice == "5":
            if delete_category(state):
                changed = True
            input("\nPress Enter to continue...")
        
        elif choice == "6":
            if changed:
                save_state(state_path, state)
                print("\n✓ Changes saved.")
                print("\n" + "="*70)
                print("⚠ IMPORTANT: Render index.html to apply changes")
                print("="*70)
                print("\nRun this command to update the HTML:")
                print("  dms render")
                print("\nOr from the main menu, press '1' and then 'render'")
                print("="*70)
            print("\nGoodbye!")
            return 0
        
        elif choice == "7":
            if changed:
                confirm = input("\n⚠ You have unsaved changes. Exit anyway? [y/N]: ").strip().lower()
                if confirm != 'y':
                    continue
            print("Goodbye!")
            return 0
        
        else:
            print("Invalid choice")

def main():
    parser = argparse.ArgumentParser(description="Interactive category manager")
    parser.add_argument("--doc", default="Doc", help="Doc directory")
    parser.add_argument("action", nargs='?', help="Action (list/add/rename/delete)")
    parser.add_argument("args", nargs='*', help="Arguments for action")
    
    args = parser.parse_args()
    
    doc_dir = Path(args.doc)
    state_path = doc_dir / ".dms_state.json"
    
    if not doc_dir.exists():
        print(f"ERROR: {doc_dir} not found")
        return 1
    
    state = load_state(state_path)
    if state is None:
        return 1
    
    # If action specified, use non-interactive mode
    if args.action:
        if args.action == "list":
            list_categories(state)
            return 0
        else:
            print("Non-interactive mode not fully implemented for this version.")
            print("Use without arguments for interactive menu.")
            return 1
    
    # Interactive mode
    return interactive_menu(state, state_path)

if __name__ == "__main__":
    sys.exit(main())
