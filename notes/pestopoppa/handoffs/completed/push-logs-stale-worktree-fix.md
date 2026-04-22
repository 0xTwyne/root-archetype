# Fix: push-logs.sh stale worktree across host/container environments

**Created:** 2026-04-21
**Priority:** Low (infrastructure hygiene)
**Scope:** `scripts/utils/push-logs.sh`

## Problem

`push-logs.sh` creates a git worktree at `$ROOT_DIR/.git/log-push-worktree`. Git stores absolute paths in worktree metadata files (`.git/worktrees/*/gitdir`). When switching between host (`/mnt/raid0/...`) and devcontainer (`/workspace/...`), the stale worktree metadata references paths that don't exist in the current environment, causing:

```
push-logs: worktree checkout failed
```

The worktree exists on disk but git can't resolve its internal pointers.

## Fix

Add stale worktree detection + pruning before the checkout attempt. Insert after line 28 (after fetch), before the "Create worktree if missing" block:

```bash
# Prune stale worktrees (handles host/container path mismatches)
git -C "$ROOT_DIR" worktree prune 2>/dev/null || true

# If worktree dir exists but git doesn't recognize it, remove and recreate
if [[ -d "$WORKTREE_DIR" ]]; then
    if ! git -C "$WORKTREE_DIR" rev-parse --git-dir &>/dev/null; then
        rm -rf "$WORKTREE_DIR"
    fi
fi
```

## File to change

`scripts/utils/push-logs.sh` — this propagates to all new projects seeded from root-archetype.

## Testing

1. Create a worktree from host, then run `push-logs.sh` from a devcontainer (or vice versa)
2. Verify it prunes the stale worktree, recreates cleanly, and pushes logs
3. Run again to confirm idempotency
