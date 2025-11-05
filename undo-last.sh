#!/bin/bash

# =========================================================================
# UNDO LAST COMMIT (SAFE REVERT)
# This script performs a safe 'git revert HEAD' for the last commit.
# It then guides the user to complete the action by pushing the fix.
# =========================================================================

# Function to simulate 'pause' for user confirmation
function pause_for_confirmation() {
  read -r -p "Press [Enter] to continue with the Revert, or Ctrl+C to stop..."
}

# Function to ask if user wants to see the full commit details
function show_commit_details() {
  read -r -p "Do you want to see the full details (the 'diff') of this commit? (y/N): " response
  case "$response" in
    [yY][eE][sS]|[yY]) 
      echo
      git show HEAD
      echo
      pause_for_confirmation
      ;;
    *)
      # Do nothing, proceed to revert prompt
      ;;
  esac
}

echo "================================================="
echo "        SAFE UNDO LAST COMMIT (REVERT)"
echo "================================================="
echo "This will create a NEW commit that cancels out the last commit."
echo "This is the safest way to undo a commit that is already on the web."
echo

# 1. Check if we are in a Git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "❌ ERROR: This directory is not a Git repository." >&2
    exit 1
fi

echo "Repo: $(basename "$(pwd)")"
LAST_COMMIT_SHA=$(git log -1 --pretty=format:"%h")

echo "Last Commit (to be undone):"
git log -1 --pretty=format:"%h %an: %s"
echo
echo "ID: $LAST_COMMIT_SHA"

# Offer to show details before pausing
show_commit_details

# Final confirmation before running revert
pause_for_confirmation

# 2. Perform the Revert
echo
echo "Starting 'git revert HEAD'..."
echo "A text editor will open. Simply SAVE and CLOSE the file to finalize the undo."
echo "-------------------------------------------------"

# Use 'git revert HEAD'
git revert HEAD

# Check if the revert was successful (i.e., the user didn't abort the commit)
if [ $? -eq 0 ]; then
    echo "-------------------------------------------------"
    echo "✅ Success: The 'undo' commit has been created locally."
    echo
    echo ">>> FINAL STEP: PUSH THE FIX <<<"
    echo "Run your sync script now to send this fix to the web."
    echo "Example: ./sync-all.sh"
    echo
else
    echo "-------------------------------------------------"
    echo "❌ Revert was aborted or failed. No changes were made."
fi

exit 0

