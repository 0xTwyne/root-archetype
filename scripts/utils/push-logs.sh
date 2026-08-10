#!/bin/bash
set -euo pipefail

# Push logs/notes to their destination.
#
# Primary path (split mode): commit+push to the log repo (no branch protections,
# no worktree dance needed).
#
# Fallback path: if log repo is unresolvable (pre-init, broken path), use the
# legacy worktree approach to push logs/notes to main on the root repo.
#
# Safe to call mid-session. Idempotent.

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"
LOCK_FILE="$ROOT_DIR/.push-logs.lock"

fail() {
    echo "push-logs: ERROR — $*" >&2
    exit 1
}

# Verify git can actually operate on a repo before trusting any of its output.
# Without this the script could report "nothing to push" while silently doing
# nothing: a failure such as "dubious ownership" writes to stderr and prints
# NOTHING to stdout, so `git status --porcelain` looks exactly like a clean
# tree. That silently dropped a session's logs in a downstream project.
check_git_repo() {
    local dir="$1" label="$2" err=""
    if ! err="$(git -C "$dir" rev-parse --git-dir 2>&1 >/dev/null)"; then
        echo "push-logs: ERROR — cannot operate on $label ($dir)" >&2
        [[ -n "$err" ]] && echo "$err" | sed 's/^/  /' >&2
        if [[ "$err" == *"dubious ownership"* ]]; then
            echo "  Cause: the repo is owned by a different uid than the current user." >&2
            echo "  Workaround for this shell:" >&2
            echo "    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='"'"'*'"'"'" >&2
            echo "  Persistent fix: chown the repo to the container user, or add" >&2
            echo "    git config --global --add safe.directory $dir" >&2
        fi
        exit 1
    fi
}

# Source hook utilities for log repo resolution
if [[ -f "$ROOT_DIR/scripts/hooks/lib/hook-utils.sh" ]]; then
    PROJECT_DIR="$ROOT_DIR"
    source "$ROOT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
    hook_resolve_log_repo 2>/dev/null || true
fi

# Load session ID for commit messages
SESSION_ID=""
if [[ -f "$ROOT_DIR/.session-identity" ]]; then
    SESSION_ID="$(jq -r '.session_id // empty' "$ROOT_DIR/.session-identity" 2>/dev/null || echo "")"
fi

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

# --- Primary path: split mode (log repo is separate) ---
if [[ -n "${LOG_REPO_DIR:-}" && "$LOG_REPO_DIR" != "$ROOT_DIR" && -d "$LOG_REPO_DIR/.git" ]]; then

    # Regenerate handoff index in log repo
    if [[ -x "$ROOT_DIR/scripts/utils/generate-handoff-index.sh" ]]; then
        bash "$ROOT_DIR/scripts/utils/generate-handoff-index.sh" "$LOG_REPO_DIR" 2>/dev/null || true
    fi

    check_git_repo "$LOG_REPO_DIR" "log repo"
    cd "$LOG_REPO_DIR"

    # Stage all log/note/wiki content. Every git call below is checked: a
    # swallowed failure here means logs are lost with a success message on
    # screen.
    git add logs/ notes/ wiki/ || fail "git add failed in $LOG_REPO_DIR"

    STATUS="$(git status --porcelain -- logs/ notes/ wiki/)" \
        || fail "git status failed in $LOG_REPO_DIR"

    if [[ -n "$STATUS" ]]; then
        git commit -q -m "logs: session ${SESSION_ID:-unknown} (auto)" \
            || fail "git commit failed in $LOG_REPO_DIR (pre-commit hook? no identity configured?)"
        GIT_TERMINAL_PROMPT=0 git push origin main \
            || fail "push to log repo failed — logs are committed locally but NOT pushed"
        echo "push-logs: pushed to log repo"
    else
        echo "push-logs: nothing to push"
    fi

    exit 0
fi

# --- Fallback path: legacy worktree approach (single-repo / pre-init) ---
WORKTREE_DIR="$ROOT_DIR/.git/log-push-worktree"

check_git_repo "$ROOT_DIR" "root repo"

# Fetch latest main
GIT_TERMINAL_PROMPT=0 git -C "$ROOT_DIR" fetch origin main \
    || fail "fetch failed — cannot push logs (offline, or no access to origin)"

# Prune stale worktrees (handles host/container path mismatches)
git -C "$ROOT_DIR" worktree prune 2>/dev/null || true

# If worktree dir exists but git doesn't recognize it, remove and recreate
if [[ -d "$WORKTREE_DIR" ]]; then
    if ! git -C "$WORKTREE_DIR" rev-parse --git-dir &>/dev/null; then
        rm -rf "$WORKTREE_DIR"
    fi
fi

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
for dir in logs notes; do
    if [[ -d "$ROOT_DIR/$dir" ]]; then
        rsync -a --ignore-existing "$ROOT_DIR/$dir/" "$WORKTREE_DIR/$dir/" 2>/dev/null || true
        rsync -a --update "$ROOT_DIR/$dir/" "$WORKTREE_DIR/$dir/" 2>/dev/null || true
    fi
done

# Regenerate handoff index in worktree
if [[ -x "$ROOT_DIR/scripts/utils/generate-handoff-index.sh" ]]; then
    bash "$ROOT_DIR/scripts/utils/generate-handoff-index.sh" "$WORKTREE_DIR" 2>/dev/null || true
fi

# Check if anything changed
cd "$WORKTREE_DIR"
STATUS="$(git status --porcelain -- logs/ notes/)" \
    || fail "git status failed in worktree $WORKTREE_DIR"

if [[ -n "$STATUS" ]]; then
    git add logs/ notes/ || fail "git add failed in worktree $WORKTREE_DIR"
    git commit -q -m "Push logs/notes to main (auto)" \
        || fail "git commit failed in worktree $WORKTREE_DIR"
    GIT_TERMINAL_PROMPT=0 git push origin HEAD:main \
        || fail "push to main failed (conflict?) — logs committed locally but NOT pushed"
    echo "push-logs: pushed to main"
else
    echo "push-logs: nothing to push"
fi
