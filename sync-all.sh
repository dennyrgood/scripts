#!/bin/bash

# =========================================================================
# Enhanced Sync Script (Minimalist Output with A/M/D Status)
# Runs from ANYWHERE: Automatically finds and synchronizes all Git 
# repositories within the directory containing the script's parent folder.
# Prints detailed output ONLY for changes or errors.
# =========================================================================

# Exit immediately if a command exits with a non-zero status, unless handled.
set -e

# --- 0. INITIAL SETUP ---

# Get the directory where this script file lives.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Set the root directory for all repositories to the PARENT directory of the script.
REPO_ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# Store the directory where the script was launched from.
START_DIR=$(pwd)
# Initialize error counter
ERROR_COUNT=0

echo "========================================="
echo " Starting Universal Git Sync (Minimalist)"
echo "========================================="
echo ""
echo "Repository Root Directory: $REPO_ROOT_DIR"

# --- 1. PROMPT FOR COMMIT MESSAGE ---

echo ""
echo "Enter commit message for any repos with changes (or press Enter for default):"
read -r COMMIT_MESSAGE

if [ -z "$COMMIT_MESSAGE" ]; then
    COMMIT_MESSAGE="Auto-sync from local changes"
fi

echo ""
echo "--- Using commit message: \"$COMMIT_MESSAGE\" ---"
echo ""

# --- 2. FIND ALL REPOSITORIES ---

# Find all .git directories starting the search from the root, excluding backups
REPOS=()
while IFS= read -r DIR; do
    REPO_PATH=$(dirname "$DIR")
    # Simple check to skip directories containing common backup strings (case-insensitive check)
    if [[ "$REPO_PATH" =~ \.BKUP|\.BAK|\.bkup|\.bak ]]; then
        continue
    fi
    REPOS+=("$REPO_PATH")
done < <(find "$REPO_ROOT_DIR" -maxdepth 3 -type d -name ".git" -not -path "$REPO_ROOT_DIR/.git")

REPO_COUNT=${#REPOS[@]}
echo "Found $REPO_COUNT repositories to process."
echo "-----------------------------------------"

# --- 3. LOOP THROUGH REPOSITORIES ---

for REPO_PATH in "${REPOS[@]}"; do
    
    REPO_NAME=$(basename "$REPO_PATH")

    # Double check to ensure we aren't processing backup directories. 
    if [[ "$REPO_NAME" =~ \.BKUP|\.BAK|\.bkup|\.bak ]]; then
        continue
    fi
    
    # Initialize status variables for this repo
    COMMITTED_CHANGES=""
    PULLED_CHANGES=""
    WAS_UP_TO_DATE=true
    
    # Capture the HEAD commit hash BEFORE the pull, to use for diff later.
    PRE_PULL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")

    # Change to the repository directory
    cd "$REPO_PATH"
    
    # --- STAGE & COMMIT BLOCK ---
    
    # Stage all changes (A for added, M for modified, D for deleted)
    git add -A
    
    # Check if there are changes to commit
    STAGED_FILES=$(git diff --name-only --staged)
    
    if [ -n "$STAGED_FILES" ]; then
        WAS_UP_TO_DATE=false
        
        # Commit changes, suppressing verbose output. Use --no-verify to bypass hooks.
        COMMIT_OUTPUT=$(git commit -m "$COMMIT_MESSAGE" --no-verify 2>&1)
        
        # Check if commit was successful
        if echo "$COMMIT_OUTPUT" | grep -q 'file changed'; then
            LAST_COMMIT_HASH=$(git rev-parse HEAD)
            # Use diff-tree to get the file status (A, M, D) for the latest commit
            COMMITTED_CHANGES=$(git diff-tree --no-commit-id --name-status "$LAST_COMMIT_HASH" | awk '{print $1 "   " $2}')
        else
            echo "❌ ERROR: Commit failed for $REPO_NAME." | tee >(cat >&2)
            ERROR_COUNT=$((ERROR_COUNT + 1))
            cd "$START_DIR"
            continue
        fi
    fi
    
    # --- PULL BLOCK (Web -> Mac) ---
    
    # Run pull and capture output, ignoring errors initially to check for conflicts
    PULL_OUTPUT=$(git pull --rebase 2>&1)
    PULL_EXIT_CODE=$?

    if [ $PULL_EXIT_CODE -ne 0 ] && echo "$PULL_OUTPUT" | grep -q 'CONFLICT'; then
        echo "❌ PULL FAILED! Please resolve conflicts manually in $REPO_PATH" | tee >(cat >&2)
        ERROR_COUNT=$((ERROR_COUNT + 1))
        cd "$START_DIR"
        continue
    elif [ $PULL_EXIT_CODE -ne 0 ] && echo "$PULL_OUTPUT" | grep -q 'Could not find remote branch'; then
        # This handles repos with no upstream branch set (rare, but happens)
        echo "⚠️ WARNING: Skipping pull for $REPO_NAME (No upstream branch set)."
        # Set WAS_UP_TO_DATE to false if we committed anything locally, so it pushes.
    elif echo "$PULL_OUTPUT" | grep -q 'Fast-forward\|Receiving objects'; then
        WAS_UP_TO_DATE=false
        
        # FIX: Robustly get changes by diffing current HEAD against the HEAD before the pull.
        if [ -n "$PRE_PULL_HEAD" ] && ! git diff --quiet "$PRE_PULL_HEAD" HEAD; then
            PULLED_CHANGES=$(git diff --name-status "$PRE_PULL_HEAD" HEAD | awk '{print $1 "   " $2}')
        fi

    elif ! echo "$PULL_OUTPUT" | grep -q 'up to date'; then
        # Catch for any successful rebase/pull that wasn't a fast-forward, but still changed things
        WAS_UP_TO_DATE=false
        # Similar robust diffing check
        if [ -n "$PRE_PULL_HEAD" ] && ! git diff --quiet "$PRE_PULL_HEAD" HEAD; then
            PULLED_CHANGES=$(git diff --name-status "$PRE_PULL_HEAD" HEAD | awk '{print $1 "   " $2}')
        fi
    fi

    # --- PUSH BLOCK (Mac -> Web) ---
    
    PUSH_OUTPUT=$(git push 2>&1)

    if echo "$PUSH_OUTPUT" | grep -q 'Everything up-to-date'; then
        # Quiet push, nothing happened
        : # Do nothing
    elif echo "$PUSH_OUTPUT" | grep -q 'error'; then
        # Push failure
        echo "❌ PUSH FAILED for $REPO_NAME" | tee >(cat >&2)
        echo "   Details: $PUSH_OUTPUT" | tee >(cat >&2)
        ERROR_COUNT=$((ERROR_COUNT + 1))
        cd "$START_DIR"
        continue
    fi
    
    # --- OUTPUT GENERATION ---
    
    if [ "$WAS_UP_TO_DATE" = true ] && [ -z "$COMMITTED_CHANGES" ] && [ -z "$PULLED_CHANGES" ]; then
        # Minimalist output for clean repos
        echo "✓ $REPO_NAME: Up-to-date"
    else
        # Detailed output block for active repos
        echo "✅ SYNCED: $REPO_NAME"
        
        # Log Pulled Changes (Web -> Mac)
        if [ -n "$PULLED_CHANGES" ]; then
            echo "   --- ⬇️ UPDATED FROM WEB -------------------"
            # Replace status codes with descriptions
            echo "$PULLED_CHANGES" | sed \
                -e 's/^A/A (Added)/' \
                -e 's/^M/M (Modified)/' \
                -e 's/^D/D (Deleted)/' \
                -e 's/ *//' | sed 's/^/   /' 
            echo "   -----------------------------------------"
        fi

        # Log Committed & Pushed Changes (Mac -> Web)
        if [ -n "$COMMITTED_CHANGES" ]; then
            echo "   --- COMMITTED & SYNCED CHANGES ----------"
            # Replace status codes with descriptions
            echo "$COMMITTED_CHANGES" | sed \
                -e 's/^A/A (Added)/' \
                -e 's/^M/M (Modified)/' \
                -e 's/^D/D (Deleted)/' \
                -e 's/ *//' | sed 's/^/   /'
            echo "   -----------------------------------------"
        fi
    fi

    # Return to the starting directory after processing this repo
    cd "$START_DIR"
    
done

# --- 4. FINAL SUMMARY ---

echo "-----------------------------------------"
echo "         SUMMARY & ERRORS"
echo "-----------------------------------------"

if [ $ERROR_COUNT -gt 0 ]; then
    echo "🚨 $ERROR_COUNT repository(ies) encountered an error. Please check the logs above." | tee >(cat >&2)
else
    echo "All repositories processed successfully."
fi
echo "========================================="

