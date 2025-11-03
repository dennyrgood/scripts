#!/bin/bash

# =========================================================================
# Enhanced Sync Script
# Runs from ANYWHERE: Automatically finds and synchronizes all Git 
# repositories within the directory containing the script's parent folder.
# =========================================================================

# Exit immediately if a command exits with a non-zero status.
# The previous version used 'set -e' but only on the start. Adding it again.
set -e

echo "========================================="
echo " Starting Universal Git Sync "
echo "========================================="
echo ""

# --- 0. DETERMINE REPOSITORY ROOT DIRECTORY ---

# Get the directory where this script file lives.
# Note: BASH_SOURCE[0] holds the path used to execute the script.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Set the root directory for all repositories to the PARENT directory of the script.
# If the script is in: /MyWebsiteGIT/Scripts
# Then the REPO_ROOT_DIR will be: /MyWebsiteGIT/
REPO_ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Repository Root Directory: $REPO_ROOT_DIR"
echo ""

# --- 1. PROMPT FOR COMMIT MESSAGE ---

# Prompt for commit message once
echo "Enter commit message for any repos with changes (or press Enter for default):"
read -r COMMIT_MESSAGE

if [ -z "$COMMIT_MESSAGE" ]; then
    COMMIT_MESSAGE="Auto-sync from local changes"
fi

echo ""
echo "--- Using commit message: \"$COMMIT_MESSAGE\" ---"
echo ""

# --- 2. FIND ALL REPOSITORIES (AUTOMATIC DISCOVERY) ---

# Find all .git directories starting the search from the determined REPO_ROOT_DIR.
# Exclude directories containing backup suffixes (*.BKUP, *.bkp, *.BKUP-*).
REPOS=()
while IFS= read -r DIR; do
    # Strip the trailing /.git to get the repository path
    REPO_PATH="${DIR%/.git}"
    # Ensure the script's directory itself (if it's a repo) is processed, but only once
    if [ "$REPO_PATH" == "$SCRIPT_DIR" ]; then
        # If the script folder is a repo, it must be the first element
        REPOS=("${REPO_PATH}" "${REPOS[@]}")
        continue
    fi
    REPOS+=("$REPO_PATH")
done < <(
    # The find command now starts from the absolute path of REPO_ROOT_DIR
    # It finds all .git directories, pruning out any directories matching backup patterns.
    find "$REPO_ROOT_DIR" -type d \( -name "*.BKUP" -o -name "*.bkp" -o -name "*.BKUP-*" \) -prune -o -type d -name ".git" -print
)

# Remove duplicates (important if the script folder is found multiple times)
REPOS=($(printf "%s\n" "${REPOS[@]}" | sort -u))


if [ ${#REPOS[@]} -eq 0 ]; then
    echo "❌ Error: No git repositories found in '$REPO_ROOT_DIR' or its subdirectories."
    exit 1
fi

echo "Found ${#REPOS[@]} repositories to process."

# --- 3. LOOP AND SYNC ---

# Store the starting directory
START_DIR=$(pwd)

# Loop through each repo
for REPO_PATH in "${REPOS[@]}"; do
    
    # Calculate the relative name for display
    REPO_NAME=$(basename "$REPO_PATH")

    echo "========================================="
    echo "Syncing: $REPO_NAME ($REPO_PATH)"
    echo "========================================="
    
    # Change to repo directory
    if ! cd "$REPO_PATH" 2>/dev/null; then
        echo "❌ Error: Could not access $REPO_PATH"
        continue
    fi
    
    # Stage all changes
    echo "Staging changes..."
    git add -A
    
    # Check if there are changes to commit
    if git diff --staged --quiet; then
        echo "✓ No changes to commit."
    else
        # Log the files about to be committed (Local changes)
        echo "--- ⬆️ Files Committed Locally (Mac) --------------------"
        git diff --name-only --staged
        echo "--------------------------------------------------------"
        
        # Commit changes
        echo "Committing changes..."
        if git commit -m "$COMMIT_MESSAGE"; then
            echo "✓ Changes committed."
        else
            echo "❌ Commit failed for $REPO_NAME."
            cd "$START_DIR"
            continue
        fi
    fi
    
    # --- PULL/PUSH BLOCK ---
    
    # Pull remote changes (using rebase to avoid unnecessary merge commits)
    echo "Pulling from remote (Web -> Mac)..."
    
    # Capture the output of the pull operation to see what changed
    PULL_OUTPUT=$(git pull --rebase 2>&1)
    PULL_STATUS=$?
    
    if [ $PULL_STATUS -ne 0 ]; then
        # Display the full error output if the pull failed
        echo "$PULL_OUTPUT"
        echo "❌ PULL FAILED! Please resolve conflicts manually in $REPO_PATH"
        cd "$START_DIR"
        continue
    fi
    
    echo "✓ Pull complete."
    
    # Log the files that were updated during the pull/rebase (Web to Mac changes)
    if echo "$PULL_OUTPUT" | grep -q "Fast-forward\|Updated"; then
        echo "--- ⬇️ Files Updated from Web (Pull) -------------------"
        # Find files updated by the last pull (which is a merge or rebase)
        PULLED_FILES=$(git log --pretty=format: --name-only --since='5 seconds ago' | sort -u)
        if [ -n "$PULLED_FILES" ]; then
            echo "$PULLED_FILES"
        else
            echo "No files updated in pull."
        fi
        echo "--------------------------------------------------------"
    else
        echo "No file changes detected during pull."
    fi

    
    # Push local changes
    echo "Pushing to remote (Mac -> Web)..."
    
    # 1. Attempt standard push
    PUSH_SUCCESS=false
    if git push; then
        PUSH_SUCCESS=true
        echo "✓ Successfully synced $REPO_NAME"
    # 2. If standard push fails (e.g., first push or missing upstream), try -u
    elif git push -u origin main; then
        PUSH_SUCCESS=true
        echo "✓ Successfully synced $REPO_NAME (Set upstream branch)"
    else
        # If both attempts fail
        echo "❌ Push failed for $REPO_NAME"
    fi

    # Log the files that were pushed
    if $PUSH_SUCCESS; then
        # We can't easily capture the push output itself to see file changes, 
        # so we rely on the commit log to show what was just pushed.
        echo "--- ⬆️ Files Pushed to Web (Mac) ----------------------"
        # Note: This displays the files from the commit made locally.
        git diff --name-only "HEAD^..HEAD" || echo "No files committed or pushed."
        echo "--------------------------------------------------------"
    fi
    
    echo ""
    
    # Return to the starting directory after processing this repo
    cd "$START_DIR"
    
done

echo "========================================="
echo "All repositories processed!"
echo "========================================="

