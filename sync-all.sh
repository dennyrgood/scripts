#!/bin/bash

# =========================================================================
# Enhanced Sync Script
# Runs from ANYWHERE: Automatically finds and synchronizes all Git 
# repositories within the directory containing the script's parent folder.
# =========================================================================

# Exit immediately if a command exits with a non-zero status.
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

# --- 2. FIND ALL REPOSITORIES ---

# Find all .git directories starting the search from the determined REPO_ROOT_DIR.
REPOS=()
while IFS= read -r DIR; do
    # Strip the trailing /.git to get the repository path
    REPO_PATH="${DIR%/.git}"
    REPOS+=("$REPO_PATH")
done < <(
    # The find command now starts from the absolute path of REPO_ROOT_DIR
    find "$REPO_ROOT_DIR" -type d \( -name "*.BKUP" -o -name "*.bkp" -o -name "*.BKUP-*" \) -prune -o -type d -name ".git" -print
)

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
    # Using `2>/dev/null` suppresses 'No such file or directory' errors if any
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
        # Commit changes
        echo "Committing changes..."
        if git commit -m "$COMMIT_MESSAGE"; then
            echo "✓ Changes committed."
        else
            # This catch is for an edge case where commit fails for other reasons
            echo "❌ Commit failed for $REPO_NAME."
            cd "$START_DIR"
            continue
        fi
    fi
    
    # --- PULL/PUSH BLOCK ---
    
    # Pull remote changes (using the default remote branch set up in the repo)
    echo "Pulling from remote..."
    
    # CRITICAL SECURITY IMPROVEMENT:
    # Use `git pull --rebase` to avoid creating unnecessary merge commits when syncing.
    if ! git pull --rebase; then
        echo "❌ PULL FAILED! Please resolve conflicts manually in $REPO_PATH"
        cd "$START_DIR"
        continue
    fi
    echo "✓ Pull complete."
    
    # Push local changes
    echo "Pushing to remote..."
    if git push; then
        echo "✓ Successfully synced $REPO_NAME"
    else
        # This push error often means the pull/rebase failed above, but good to catch.
        echo "❌ Push failed for $REPO_NAME"
    fi
    
    echo ""
    
    # Return to the starting directory after processing this repo
    cd "$START_DIR"
    
done

echo "========================================="
echo "All repositories processed!"
echo "========================================="

