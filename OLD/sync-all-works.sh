#!/bin/bash

# =========================================================================
# Multi-Repository Git Sync Script
# Syncs all Git repositories on their current branches
# =========================================================================

# --- CONFIGURATION ---
USE_REBASE=false  # Set to true to use rebase instead of merge
VERIFY_COMMITS=true  # Set to false to skip pre-commit hooks
SHOW_COMMANDS=true  # Set to false to hide git command traces
DRY_RUN=false  # Set to true to see what would happen without doing it
SKIP_CLEAN_REPOS=true  # Set to false to process all repos even if up-to-date

# --- PARSE ARGUMENTS ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            echo "🔍 DRY RUN MODE - No changes will be made"
            echo ""
            shift
            ;;
        --verbose)
            SHOW_COMMANDS=true
            shift
            ;;
        --all)
            SKIP_CLEAN_REPOS=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# --- SETUP ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
START_DIR=$(pwd)
ERROR_COUNT=0
SKIP_COUNT=0

# --- COMMIT MESSAGE ---
echo "Enter commit message (or press Enter for default):"
read -r COMMIT_MESSAGE
COMMIT_MESSAGE=${COMMIT_MESSAGE:-"Auto-sync from local changes"}
echo ""

# --- FIND REPOSITORIES ---
REPOS=()
while IFS= read -r DIR; do
    REPO_PATH=$(dirname "$DIR")
    if [[ ! "$REPO_PATH" =~ \.BKUP|\.BAK|\.bkup|\.bak|_backup|_bak ]]; then
        REPOS+=("$REPO_PATH")
    fi
done < <(find "$REPO_ROOT_DIR" -maxdepth 3 -type d -name ".git" -not -path "$REPO_ROOT_DIR/.git")

echo "Found ${#REPOS[@]} repositories to sync"
echo ""

# --- PROCESS REPOSITORIES ---
for REPO_PATH in "${REPOS[@]}"; do
    REPO_NAME=$(basename "$REPO_PATH")
    REPO_FAILED=false
    HAS_CHANGES=false
    
    cd "$REPO_PATH" || { 
        echo "✗ $REPO_NAME: Cannot access directory" >&2
        ERROR_COUNT=$((ERROR_COUNT + 1))
        cd "$START_DIR"
        continue
    }
    
    echo "📂 $REPO_NAME"
    
    # --- CHECK FOR DETACHED HEAD ---
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    
    if [ "$CURRENT_BRANCH" = "HEAD" ]; then
        echo "   ⚠   Detached HEAD state - skipping (not on any branch)" >&2
        echo "      Run: git checkout -b <branch-name> to create a branch"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        echo ""
        cd "$START_DIR"
        continue
    fi
    
    echo "   Branch: $CURRENT_BRANCH"
    
    # --- FETCH TAGS ---
    if [ "$SHOW_COMMANDS" = true ]; then
        echo "   📍 Running: git fetch --tags"
    fi
    git fetch --tags --quiet 2>/dev/null
    
    # --- CHECK FOR CHANGES ---
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        HAS_CHANGES=true
        echo "   Files changed:"
        git status --short | sed 's/^/      /'
        echo ""
    fi
    
    # --- SKIP IF NO CHANGES AND UP-TO-DATE ---
    if [ "$HAS_CHANGES" = false ] && [ "$SKIP_CLEAN_REPOS" = true ]; then
        git fetch origin "$CURRENT_BRANCH" --quiet 2>/dev/null
        LOCAL=$(git rev-parse @ 2>/dev/null)
        REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")
        
        if [ "$LOCAL" = "$REMOTE" ] && [ -n "$REMOTE" ]; then
            echo "   ✓ Up-to-date (skipped)"
            echo ""
            cd "$START_DIR"
            continue
        fi
    fi
    
    # --- COMMIT LOCAL CHANGES ---
    if [ "$SHOW_COMMANDS" = true ]; then
        echo "   📍 Running: git add -A"
    fi
    git add -A
    
    if ! git diff --staged --quiet 2>/dev/null; then
        # List changed files
        echo "   Changes to commit:"
        git diff --staged --name-status | while read status file; do
            case "$status" in
                A) echo "      + $file" ;;
                M) echo "      ~ $file" ;;
                D) echo "      - $file" ;;
                *) echo "      $status $file" ;;
            esac
        done
        
        # Commit with or without verification based on config
        COMMIT_CMD="git commit -m \"$COMMIT_MESSAGE\""
        if [ "$VERIFY_COMMITS" = false ]; then
            COMMIT_CMD="$COMMIT_CMD --no-verify"
        fi
        
        if [ "$SHOW_COMMANDS" = true ]; then
            echo "   📍 Running: $COMMIT_CMD"
        fi
        
        if [ "$DRY_RUN" = true ]; then
            echo "   [DRY RUN] Would commit changes"
        elif eval "$COMMIT_CMD" &>/dev/null; then
            echo "   ✓ Committed"
        else
            echo "   ✗ Commit failed" >&2
            if [ "$VERIFY_COMMITS" = true ]; then
                echo "      Tip: Pre-commit hooks may have rejected the commit"
                echo "      Check output with: cd $REPO_PATH && git commit"
            fi
            ERROR_COUNT=$((ERROR_COUNT + 1))
            REPO_FAILED=true
        fi
    fi
    
    # Skip pull/push if commit failed
    if [ "$REPO_FAILED" = true ]; then
        echo ""
        cd "$START_DIR"
        continue
    fi
    
    # --- PULL FROM REMOTE ---
    PULL_CMD="git pull"
    if [ "$USE_REBASE" = true ]; then
        PULL_CMD="$PULL_CMD --rebase"
    fi
    PULL_CMD="$PULL_CMD origin $CURRENT_BRANCH"
    
    if [ "$SHOW_COMMANDS" = true ]; then
        echo "   📍 Running: $PULL_CMD"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo "   [DRY RUN] Would pull from origin/$CURRENT_BRANCH"
        PULL_OUTPUT="Already up to date."
        PULL_EXIT=0
    else
        PULL_OUTPUT=$($PULL_CMD 2>&1)
        PULL_EXIT=$?
    fi
    
    if [ $PULL_EXIT -ne 0 ]; then
        # Check for specific error types
        if echo "$PULL_OUTPUT" | grep -qi "conflict"; then
            echo "   ✗ MERGE CONFLICT detected" >&2
            echo "      Resolve manually: cd $REPO_PATH" >&2
            echo "      Then run: git status" >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            REPO_FAILED=true
        elif echo "$PULL_OUTPUT" | grep -qi "no tracking\|does not exist"; then
            echo "   ⚠   No upstream branch set for $CURRENT_BRANCH"
            echo "      Will set on push with -u flag"
        elif echo "$PULL_OUTPUT" | grep -qi "uncommitted changes"; then
            echo "   ✗ Pull blocked by uncommitted changes" >&2
            echo "      Stash or commit changes first" >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            REPO_FAILED=true
        else
            echo "   ✗ Pull failed" >&2
            echo "      Error: $(echo "$PULL_OUTPUT" | head -n 2)" >&2
            ERROR_COUNT=$((ERROR_COUNT + 1))
            REPO_FAILED=true
        fi
    elif ! echo "$PULL_OUTPUT" | grep -qi "up.to.date\|already up to date"; then
        echo "   ↓ Pulled changes"
    fi
    
    # Skip push if pull failed
    if [ "$REPO_FAILED" = true ]; then
        echo ""
        cd "$START_DIR"
        continue
    fi
    
    # --- PUSH TO REMOTE ---
    # Use -u flag to set upstream tracking for new branches
    if [ "$SHOW_COMMANDS" = true ]; then
        echo "   📍 Running: git push -u origin $CURRENT_BRANCH"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo "   [DRY RUN] Would push to origin/$CURRENT_BRANCH"
        PUSH_OUTPUT="Everything up-to-date"
        PUSH_EXIT=0
    else
        PUSH_OUTPUT=$(git push -u origin "$CURRENT_BRANCH" 2>&1)
        PUSH_EXIT=$?
    fi
    
    if [ $PUSH_EXIT -ne 0 ]; then
        if echo "$PUSH_OUTPUT" | grep -qi "rejected"; then
            echo "   ✗ Push rejected - remote has changes" >&2
            echo "      Pull and resolve conflicts first" >&2
        elif echo "$PUSH_OUTPUT" | grep -qi "permission denied\|authentication failed"; then
            echo "   ✗ Push failed - authentication/permission error" >&2
        elif echo "$PUSH_OUTPUT" | grep -qi "network\|connection"; then
            echo "   ✗ Push failed - network error" >&2
        else
            echo "   ✗ Push failed" >&2
            echo "      Error: $(echo "$PUSH_OUTPUT" | head -n 2)" >&2
        fi
        ERROR_COUNT=$((ERROR_COUNT + 1))
    elif ! echo "$PUSH_OUTPUT" | grep -qi "up.to.date\|everything up-to-date"; then
        if echo "$PUSH_OUTPUT" | grep -qi "new branch"; then
            echo "   ↑ Pushed (new branch, upstream set)"
        else
            echo "   ↑ Pushed changes"
        fi
    fi
    
    echo ""
    cd "$START_DIR"
done

# --- SUMMARY ---
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_REPOS=${#REPOS[@]}
SUCCESS_COUNT=$((TOTAL_REPOS - ERROR_COUNT - SKIP_COUNT))

echo "Processed: $TOTAL_REPOS repositories"
echo "Success:   $SUCCESS_COUNT"
if [ $SKIP_COUNT -gt 0 ]; then
    echo "Skipped:   $SKIP_COUNT"
fi
if [ $ERROR_COUNT -gt 0 ]; then
    echo "Errors:    $ERROR_COUNT"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERROR_COUNT -gt 0 ]; then
    echo "⚠   Completed with errors - review output above"
    exit 1
elif [ $SKIP_COUNT -gt 0 ]; then
    echo "✓ Completed with $SKIP_COUNT skipped"
    exit 0
else
    echo "✓ All repositories synced successfully"
    exit 0
fi
