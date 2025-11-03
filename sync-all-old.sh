#!/bin/bash

# Master sync script to sync all repos in MyWebsiteGIT
# Usage: Run this from anywhere, it will find and sync all your repos

# Get the directory where this script lives
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Parent directory containing all repos
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# List of repos to sync
REPOS=("dennyrgood.github.io" "USDZ_AVP" "weather-dashboard")

echo "========================================="
echo "Starting sync for all repositories"
echo "========================================="
echo ""

# Prompt for commit message once (will be used for all repos that have changes)
echo "Enter commit message for any repos with changes (or press Enter for default):"
read -r COMMIT_MESSAGE

if [ -z "$COMMIT_MESSAGE" ]; then
    COMMIT_MESSAGE="Cleaning up files/sync from local to web"
fi

echo ""
echo "--- Using commit message: \"$COMMIT_MESSAGE\" ---"
echo ""

# Loop through each repo
for REPO in "${REPOS[@]}"; do
    REPO_PATH="$PARENT_DIR/$REPO"
    
    echo "========================================="
    echo "Syncing: $REPO"
    echo "========================================="
    
    # Check if repo exists
    if [ ! -d "$REPO_PATH" ]; then
        echo "⚠️  Warning: $REPO not found at $REPO_PATH"
        echo ""
        continue
    fi
    
    # Change to repo directory
    cd "$REPO_PATH" || {
        echo "❌ Error: Could not access $REPO"
        echo ""
        continue
    }
    
    # Check if it's a git repo
    if [ ! -d ".git" ]; then
        echo "⚠️  Warning: $REPO is not a git repository"
        echo ""
        continue
    fi
    
    # Stage all changes
    echo "Staging changes..."
    git add -A
    
    # Check if there are changes to commit
    if git diff --staged --quiet; then
        echo "✓ No changes to commit"
    else
        # Commit changes
        echo "Committing changes..."
        git commit -m "$COMMIT_MESSAGE"
        
        if [ $? -eq 0 ]; then
            echo "✓ Changes committed"
        else
            echo "❌ Commit failed"
        fi
    fi
    
    # Pull remote changes
    echo "Pulling from remote..."
    git pull origin main
    
    if [ $? -ne 0 ]; then
        echo "❌ Pull failed - please resolve conflicts manually"
        echo "   Repository: $REPO_PATH"
        echo ""
        continue
    fi
    
    # Push local changes
    echo "Pushing to remote..."
    git push origin main
    
    if [ $? -eq 0 ]; then
        echo "✓ Successfully synced $REPO"
    else
        echo "❌ Push failed for $REPO"
    fi
    
    echo ""
done

echo "========================================="
echo "All repositories processed!"
echo "========================================="

# Return to original directory
cd "$PARENT_DIR"
