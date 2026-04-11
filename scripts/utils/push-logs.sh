#!/bin/bash
set -euo pipefail

# Push logs/notes directly to main (append-only, no PR friction)
# Uses a worktree to avoid disrupting current git state.
# Safe to call mid-session.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"
LOCK_FILE="$ROOT_DIR/.push-logs.lock"
WORKTREE_DIR="$ROOT_DIR/.git/log-push-worktree"

# Lock with 60-second staleness
if [[ -f "$LOCK_FILE" ]]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0) ))
    if [[ $LOCK_AGE -lt 60 ]]; then
        echo "push-logs: locked (age=${LOCK_AGE}s), skipping"
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Fetch latest main
GIT_TERMINAL_PROMPT=0 git -C "$ROOT_DIR" fetch origin main 2>/dev/null || {
    echo "push-logs: fetch failed, skipping"
    exit 0
}

# Create worktree if missing
if [[ ! -d "$WORKTREE_DIR" ]]; then
    git -C "$ROOT_DIR" worktree add "$WORKTREE_DIR" origin/main --detach 2>/dev/null || {
        echo "push-logs: worktree creation failed"
        exit 0
    }
fi

# Update worktree to latest main
git -C "$WORKTREE_DIR" checkout --detach origin/main 2>/dev/null || {
    echo "push-logs: worktree checkout failed"
    exit 0
}

# Copy logs and notes (append-only = clean merge)
CHANGED=false
for dir in logs notes; do
    if [[ -d "$ROOT_DIR/$dir" ]]; then
        rsync -a --ignore-existing "$ROOT_DIR/$dir/" "$WORKTREE_DIR/$dir/" 2>/dev/null || true
        # Also sync modified files (newer than worktree version)
        rsync -a --update "$ROOT_DIR/$dir/" "$WORKTREE_DIR/$dir/" 2>/dev/null || true
    fi
done

# Regenerate handoff index in worktree
if [[ -x "$ROOT_DIR/scripts/utils/generate-handoff-index.sh" ]]; then
    bash "$ROOT_DIR/scripts/utils/generate-handoff-index.sh" "$WORKTREE_DIR" 2>/dev/null || true
fi

# Check if anything changed
cd "$WORKTREE_DIR"
if [[ -n "$(git status --porcelain -- logs/ notes/ 2>/dev/null)" ]]; then
    git add logs/ notes/ 2>/dev/null || true
    git commit -m "Push logs/notes to main (auto)" 2>/dev/null || true
    GIT_TERMINAL_PROMPT=0 git push origin HEAD:main 2>/dev/null || {
        echo "push-logs: push failed (conflict?)"
        exit 0
    }
    echo "push-logs: pushed to main"
else
    echo "push-logs: nothing to push"
fi
