#!/bin/bash
# Quick status check for current git repo

echo "=== Current Branch ==="
CURRENT_BRANCH=$(git branch --show-current)
echo "$CURRENT_BRANCH"

# Show if branch has upstream
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
if [ -n "$UPSTREAM" ]; then
    echo "Tracking: $UPSTREAM"
    
    # Show if ahead/behind
    git fetch --quiet 2>/dev/null
    AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
    BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
    
    if [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -gt 0 ]; then
        echo "⚠️  $AHEAD ahead, $BEHIND behind (need to pull and push)"
    elif [ "$AHEAD" -gt 0 ]; then
        echo "↑ $AHEAD commit(s) ahead (need to push)"
    elif [ "$BEHIND" -gt 0 ]; then
        echo "↓ $BEHIND commit(s) behind (need to pull)"
    else
        echo "✓ Up to date with remote"
    fi
else
    echo "⚠️  No upstream branch set"
fi

echo ""
echo "=== Files Changed ==="
if git diff --quiet && git diff --staged --quiet; then
    echo "✓ No changes"
else
    git status --short
fi

echo ""
echo "=== Last 5 Commits ==="
git log --oneline -5

echo ""
echo "=== Recent Tags ==="
TAGS=$(git tag -l --sort=-version:refname | head -5)
if [ -n "$TAGS" ]; then
    echo "$TAGS"
else
    echo "(no tags)"
fi
