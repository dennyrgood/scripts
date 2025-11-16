#!/usr/bin/env bash
set -euo pipefail

# Compact git sync with concise summary output
# Usage: ./sync-this.sh "commit message"
# If no message provided, prompts (empty -> uses default).

EMOJI_BRANCH="📂"
EMOJI_START="▶"
EMOJI_DONE="✓"
EMOJI_WARN="⚠️"
EMOJI_PIN="📍"

separator() { printf '%0.0s=' $(seq 1 42); echo; }

repo_name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo .)")
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no-repo)")

# Pre-Sync diagnostics
separator
echo "$EMOJI_BRANCH $repo_name"
separator
echo "   Branch: $current_branch"

# Upstream status
upstream=""
if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null)
  # update remote refs quietly
  git fetch --quiet || true
  ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)
  behind=$(git rev-list --count "HEAD..${upstream}" 2>/dev/null || echo 0)
  if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
    echo "   Pre-Sync Remote: $EMOJI_DONE Up to date"
  else
    echo "   Pre-Sync Remote: $EMOJI_WARN ↑ $ahead ahead, ↓ $behind behind"
  fi
else
  echo "   Pre-Sync Remote: $EMOJI_WARN No upstream"
fi

# Local file changes (staging)
staged_count=$(git diff --staged --name-only | wc -l | tr -d ' ')
unstaged_count=$(git diff --name-only | wc -l | tr -d ' ')
if [ "$staged_count" -eq 0 ] && [ "$unstaged_count" -eq 0 ]; then
  echo "   Files Changed Locally (Staging):"
  echo "       $EMOJI_DONE No changes to commit"
else
  echo "   Files Changed Locally (Staging):"
  # show staged first, then unstaged
  if [ "$staged_count" -gt 0 ]; then
    git diff --staged --name-only | sed 's/^/       M /'
  fi
  if [ "$unstaged_count" -gt 0 ]; then
    git diff --name-only | sed 's/^/       ? /'
  fi
fi

echo "   ------------------------------------------"
echo "   >>> START TRANSACTION <<<"

# Commit logic
DEFAULT_MESSAGE="Cleaning up files/sync from local to remote branch: $current_branch"
if [ "${1:-}" != "" ]; then
  commit_message="$1"
else
  printf "   %s Enter commit message (or press Enter to use default): " "$EMOJI_PIN"
  read -r user_message || user_message=""
  if [ -z "$user_message" ]; then
    commit_message="$DEFAULT_MESSAGE"
  else
    commit_message="$user_message"
  fi
fi

echo "   $EMOJI_PIN Running: git add -A"
git add -A

commit_performed=false
if git diff --staged --quiet; then
  echo "   $EMOJI_WARN No staged changes to commit"
else
  echo "   $EMOJI_PIN Running: git commit -m \"$commit_message\""
  if git commit -m "$commit_message" >/dev/null 2>&1; then
    echo "   $EMOJI_DONE Commit Successful"
    commit_performed=true
  else
    echo "   $EMOJI_WARN Commit failed or no changes committed"
  fi
fi

# Pull (merge remote changes)
echo "   $EMOJI_PIN Running: git pull origin $current_branch"
pull_output=$(git pull --no-edit origin "$current_branch" 2>&1) || pull_status=$? || pull_status=$?
pull_status=${pull_status:-0}

if [ "$pull_status" -ne 0 ]; then
  # likely merge conflict or other failure
  echo "   $EMOJI_WARN Pull failed:"
  echo "       $(echo "$pull_output" | sed -n '1,6p' | sed 's/^/       /')"
  echo ""
  echo "   Aborting sync — please resolve pull conflicts and retry."
  exit 1
else
  # summarize pull
  if echo "$pull_output" | grep -qi "Already up to date\|Already up-to-date"; then
    echo "   $EMOJI_DONE Pull: Already up to date."
  elif echo "$pull_output" | grep -qi "Fast-forward"; then
    echo "   $EMOJI_DONE Pull: Fast-forward merged remote changes."
  else
    echo "   $EMOJI_DONE Pull: Merged remote changes."
  fi
fi

# Push
echo "   $EMOJI_PIN Running: git push -u origin $current_branch"
push_output=$(git push -u origin "$current_branch" 2>&1) || push_status=$? || push_status=$?
push_status=${push_status:-0}

if [ "$push_status" -ne 0 ]; then
  echo "   $EMOJI_WARN Push failed:"
  echo "       $(echo "$push_output" | sed -n '1,6p' | sed 's/^/       /')"
  exit 1
else
  if echo "$push_output" | grep -qi "Everything up-to-date\|Already up to date"; then
    echo "   $EMOJI_DONE Push: Already up to date."
  else
    echo "   $EMOJI_DONE Push Successful."
  fi
fi

echo "   ------------------------------------------"
echo "   >>> POST-SYNC STATUS <<<"

# Post-sync concise status
# Count staged/unstaged again
staged_count_post=$(git diff --staged --name-only | wc -l | tr -d ' ')
unstaged_count_post=$(git diff --name-only | wc -l | tr -d ' ')
if [ "$staged_count_post" -eq 0 ] && [ "$unstaged_count_post" -eq 0 ]; then
  echo "   Remote: $EMOJI_DONE Up to date"
  echo "   Local: 0 unstaged/staged files."
else
  echo "   Remote: (see git status)"
  printf "   Local: %s staged, %s unstaged files\n" "$staged_count_post" "$unstaged_count_post"
fi

# Last commit short info
last_commit=$(git log --oneline -1 2>/dev/null || echo "(no commits)")
echo "   Last Commit: $last_commit"

separator
echo
