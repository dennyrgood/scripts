#!/bin/bash
# git-tools.sh - Quick reference for git commands and helper scripts
# Usage: git-tools [category]
# Categories: basics, history, undo, branches, compare, helpers, all

show_section() {
    local title="$1"
    echo ""
    echo "=========================================="
    echo "$title"
    echo "=========================================="
}

show_basics() {
    show_section "BASIC GIT COMMANDS"
    echo "git status                           # See what files have changed"
    echo "git add .                            # Stage all changes for commit"
    echo "git add <file>                       # Stage specific file"
    echo "git commit -m \"message\"              # Save snapshot with description"
    echo "git push                             # Send commits to GitHub"
    echo "git pull                             # Get latest changes from GitHub"
    echo "git fetch --tags                     # Download release tags from GitHub"
}

show_history() {
    show_section "VIEWING HISTORY"
    echo "git log --oneline                    # See recent commits (one line each)"
    echo "git log --oneline -10                # See last 10 commits"
    echo "git log --oneline <file>             # See commits that changed a file"
    echo "git log --since=\"2 days ago\"         # See recent commits by date"
    echo "git log --tags --simplify-by-decoration  # See all tagged releases"
    echo "git show <commit>                    # See details of a specific commit"
    echo "git show <commit>:<file>             # See file content at that commit"
    echo "git show HEAD                        # See your last commit"
    echo "git diff                             # See uncommitted changes"
    echo "git diff <file>                      # See changes to specific file"
}

show_undo() {
    show_section "UNDOING CHANGES"
    echo "git checkout -- <file>               # Throw away changes to one file"
    echo "git reset --hard HEAD                # Throw away ALL uncommitted changes"
    echo "git reset --soft HEAD~1              # Undo last commit, keep the changes"
    echo "git reset --hard HEAD~1              # Undo last commit, delete the changes"
    echo "git revert HEAD                      # Create new commit that undoes last one (safe)"
    echo "git checkout <commit> -- <file>      # Get old version of file"
    echo "git revert <commit>                  # Create new commit that undoes old one"
}

show_branches() {
    show_section "WORKING WITH BRANCHES"
    echo "git branch                           # List all branches"
    echo "git branch -a                        # List all branches (including remote)"
    echo "git checkout main                    # Switch to main branch"
    echo "git checkout -b <name>               # Create and switch to new branch"
    echo "git checkout <commit>                # Jump to old commit (read-only mode)"
    echo "git merge <branch>                   # Merge branch into current branch"
    echo "git branch -d <branch>               # Delete branch (safe)"
    echo "git branch -D <branch>               # Force delete branch (even if not merged)"
}

show_compare() {
    show_section "COMPARING VERSIONS"
    echo "git diff <commit1> <commit2>         # Compare two versions"
    echo "git diff <commit1> <commit2> <file>  # Compare file between versions"
    echo "git diff v2.0 v4.0                   # Compare two releases"
    echo "git diff HEAD~5 HEAD                 # Compare 5 commits ago to now"
    echo "git diff --stat <commit1> <commit2>  # Summary of changes"
    echo "git log -p -5                        # Show last 5 commits with diffs"
    echo "git log -S \"function_name\"           # Find when text was added/removed"
}

show_tags() {
    show_section "WORKING WITH TAGS/RELEASES"
    echo "git tag -l                           # List all tags"
    echo "git tag -a v1.0 -m \"message\"         # Create annotated tag"
    echo "git tag -a v1.0 <commit> -m \"msg\"    # Tag an old commit"
    echo "git push --tags                      # Push tags to GitHub"
    echo "git checkout v1.0                    # Jump to tagged version"
    echo "git tag -d v1.0                      # Delete tag locally"
    echo "git push origin :refs/tags/v1.0      # Delete tag on GitHub"
}

show_helpers() {
    show_section "HELPER SCRIPTS (Installed)"
    echo "get-previous <file>                  # Interactive: recover old file version"
    echo "show-history <file>                  # Show complete file history"
    echo "git-undo                             # Interactive: undo commits or changes"
    echo "safe-experiment <name>               # Create branch for experimenting"
    echo "merge-experiment [name]              # Merge successful experiment to main"
    echo "abandon-experiment                   # Discard failed experiment branch"
    echo "what-changed <c1> <c2> [file]        # Compare two versions"
    echo "sync-this.sh                         # Commit, pull, and push current branch"
}

show_common_tasks() {
    show_section "COMMON TASKS"
    echo "# See what changed"
    echo "git status                           # Current uncommitted changes"
    echo "git log --oneline -10                # Last 10 commits"
    echo "git diff                             # What I changed since last commit"
    echo ""
    echo "# Save your work"
    echo "git add .                            # Stage everything"
    echo "git commit -m \"Fixed parser bug\"     # Commit with message"
    echo "git push                             # Send to GitHub"
    echo ""
    echo "# Get old code back"
    echo "get-previous <file>                  # Use helper (easiest)"
    echo "git checkout <commit> -- <file>      # Or do it manually"
    echo ""
    echo "# Experiment safely"
    echo "safe-experiment try-new-idea         # Create branch"
    echo "# ... work on it ..."
    echo "merge-experiment                     # Worked? Merge it"
    echo "abandon-experiment                   # Failed? Delete it"
    echo ""
    echo "# Oh no, made a mistake!"
    echo "git-undo                             # Use helper (easiest)"
    echo "git checkout -- <file>               # Undo one file"
    echo "git reset --hard HEAD                # Undo everything (careful!)"
}

show_aliases() {
    show_section "SUGGESTED ALIASES (Add to ~/.zshrc)"
    echo "alias gs='git status'"
    echo "alias gl='git log --oneline -10'"
    echo "alias gd='git diff'"
    echo "alias gc='git commit -m'"
    echo "alias gp='git push'"
    echo "alias gpl='git pull'"
    echo "alias gb='git branch'"
    echo "alias gco='git checkout'"
    echo "alias gsync='./sync-this.sh'"
    echo "alias ghist='git log --oneline --all --graph --decorate'"
}

show_emergency() {
    show_section "EMERGENCY COMMANDS"
    echo "# I'm in detached HEAD state, how do I get back?"
    echo "git checkout main                    # Return to main branch"
    echo ""
    echo "# I committed to wrong branch!"
    echo "git log -1                           # Note the commit hash (abc1234)"
    echo "git checkout main                    # Switch to correct branch"
    echo "git cherry-pick abc1234              # Copy that commit here"
    echo ""
    echo "# Everything is broken, start over!"
    echo "git reset --hard HEAD                # Throw away all changes"
    echo "git checkout main                    # Make sure you're on main"
    echo "git pull                             # Get latest from GitHub"
    echo ""
    echo "# I accidentally deleted a file!"
    echo "git checkout -- <file>               # Restore from last commit"
    echo "git checkout <commit> -- <file>      # Restore from specific commit"
    echo ""
    echo "# I need to see what I had yesterday"
    echo "git log --since=\"1 day ago\" --oneline  # Find yesterday's commits"
    echo "git checkout <commit>                # Jump back to that commit"
    echo "git checkout main                    # Return to present"
}

show_category() {
    case "$1" in
        1|basics)
            show_basics
            ;;
        2|history)
            show_history
            ;;
        3|undo)
            show_undo
            ;;
        4|branches)
            show_branches
            ;;
        5|compare)
            show_compare
            ;;
        6|tags)
            show_tags
            ;;
        7|helpers)
            show_helpers
            ;;
        8|tasks)
            show_common_tasks
            ;;
        9|aliases)
            show_aliases
            ;;
        10|emergency)
            show_emergency
            ;;
        11|all|"")
            show_basics
            show_history
            show_undo
            show_branches
            show_compare
            show_tags
            show_helpers
            show_common_tasks
            show_aliases
            show_emergency
            ;;
        *)
            echo "Invalid choice"
            return 1
            ;;
    esac
}

# Main script logic
if [ -z "$1" ]; then
    # Interactive mode - no argument provided
    echo "=========================================="
    echo "Git Tools - Quick Reference"
    echo "=========================================="
    echo ""
    echo "What would you like to see?"
    echo ""
    echo "  1)  basics      - Basic git commands (status, commit, push)"
    echo "  2)  history     - Viewing history and logs"
    echo "  3)  undo        - Undoing changes and commits"
    echo "  4)  branches    - Working with branches"
    echo "  5)  compare     - Comparing versions"
    echo "  6)  tags        - Working with tags/releases"
    echo "  7)  helpers     - Helper scripts available"
    echo "  8)  tasks       - Common task workflows"
    echo "  9)  aliases     - Suggested command aliases"
    echo "  10) emergency   - When things go wrong"
    echo "  11) all         - Show everything"
    echo ""
    echo "Enter number or name (or press Enter for all):"
    read -r CHOICE
    
    if [ -z "$CHOICE" ]; then
        CHOICE="all"
    fi
    
    show_category "$CHOICE"
else
    # Command line argument provided
    show_category "$1"
fi

echo ""
