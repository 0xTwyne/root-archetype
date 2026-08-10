#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: SessionEnd
# 1. Log SESSION_END to audit trail
# 2. Push logs/notes directly to main (append-only, no PR friction)
# 3. Stage non-log changes to session branch
# 4. Commit and push session branch
# 5. Create PR if substantive changes

hook_load_identity
hook_resolve_log_repo 2>/dev/null || true

# Log session end
if [[ -f "$PROJECT_DIR/scripts/utils/agent_log.sh" ]]; then
  source "$PROJECT_DIR/scripts/utils/agent_log.sh"
  agent_session_end "Session ended for $SESSION_USER"
fi


# --- Write per-user progress report (to log repo) ---
if [[ -n "$SESSION_USER" && "$SESSION_USER" != "unknown" ]]; then
  _LOG_BASE="${LOG_REPO_DIR:-$PROJECT_DIR}"
  PROGRESS_DIR="$_LOG_BASE/logs/progress/$SESSION_USER"
  mkdir -p "$PROGRESS_DIR"
  PROGRESS_FILE="$PROGRESS_DIR/$(date -u +%Y-%m-%d).md"

  # Resolve repo name for provenance
  _REPO_NAME="$(jq -r '.root_repo // empty' "$PROJECT_DIR/.session-identity" 2>/dev/null || basename "$PROJECT_DIR")"

  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo "# Progress: $(date -u +%Y-%m-%d)" > "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
    echo "## Session: ${SESSION_ID:-unknown}" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
  else
    echo "" >> "$PROGRESS_FILE"
    echo "## Session: ${SESSION_ID:-unknown}" >> "$PROGRESS_FILE"
    echo "" >> "$PROGRESS_FILE"
  fi
  echo "- Repo: ${_REPO_NAME}" >> "$PROGRESS_FILE"
  echo "- Branch: $(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)" >> "$PROGRESS_FILE"
  echo "- Ended: $(date -u +%H:%M:%S)" >> "$PROGRESS_FILE"
fi

# --- Push logs/notes directly to main ---
if [[ -x "$PROJECT_DIR/scripts/utils/push-logs.sh" ]]; then
  # stderr is deliberately NOT silenced: push-logs reports real failures there
  # (lost logs, broken repo access). Keep `|| true` so a failure cannot break
  # session end, but let the operator actually see it.
  bash "$PROJECT_DIR/scripts/utils/push-logs.sh" || true
fi

# --- Commit non-log changes on session branch ---
# Failures here are reported loudly on stderr but never abort session end.
# Silence is the danger: this block decides whether a whole session's work is
# committed and pushed, so a masked git error means the work is quietly lost.
warn_session_end() { echo "session-end: WARNING — $*" >&2; }

# Confirm git can actually operate here BEFORE deciding anything from its
# output. This check must come first: if git cannot read the repo, the branch
# lookup below silently falls back to "main", the session/* test fails, and the
# entire commit/push block is skipped without a word. Note also that piping
# status into `wc -l` would force exit status 0, so a hard git failure (e.g.
# "dubious ownership") is invisible to the pipeline's exit code.
if ! git_err="$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>&1 >/dev/null)"; then
  warn_session_end "cannot read git repo at $PROJECT_DIR — session work NOT committed"
  [[ -n "$git_err" ]] && echo "$git_err" | sed 's/^/  /' >&2
else
  CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

  if [[ "$CURRENT_BRANCH" == session/* ]]; then
    # Stage everything except logs/ and notes/ (those went to main)
    if ! CHANGED="$(git -C "$PROJECT_DIR" status --porcelain -- ':!logs/' ':!notes/')"; then
      warn_session_end "git status failed — session work NOT committed"
      CHANGED=""
    fi

    if [[ -n "$CHANGED" ]]; then
      if ! git -C "$PROJECT_DIR" add -A -- ':!logs/' ':!notes/'; then
        warn_session_end "git add failed — session work NOT committed"
      elif ! git -C "$PROJECT_DIR" commit -q -m "Session work: ${SESSION_ID:-unknown}"; then
        warn_session_end "git commit failed — session work NOT committed"
      elif ! GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" push -u origin "$CURRENT_BRANCH"; then
        warn_session_end "push of $CURRENT_BRANCH failed — work is committed locally but NOT pushed"
      else
        # Create PR if gh is available. Only attempted once the push succeeded,
        # so this can no longer open a PR for a branch that never landed.
        if command -v gh &>/dev/null; then
          gh pr create \
            --title "Session: ${SESSION_ID:-unknown}" \
            --body "Automated session PR from $SESSION_USER" \
            --base main \
            --head "$CURRENT_BRANCH" >/dev/null 2>&1 \
            || true  # a PR often already exists for this branch; not an error
        fi
      fi
    fi
  fi
fi
