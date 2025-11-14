#!/bin/bash
# save as check-status.sh
echo "=== Current Branch ==="
git branch --show-current
echo ""
echo "=== Files Changed ==="
git status --short
echo ""
echo "=== Last 5 Commits ==="
git log --oneline -5
