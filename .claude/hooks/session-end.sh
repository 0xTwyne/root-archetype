#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/.claude/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: SessionEnd
# 1. Log SESSION_END to audit trail
# 2. Push logs/notes directly to main (append-only, no PR friction)
# 3. Stage non-log changes to session branch
# 4. Commit and push session branch
# 5. Create PR if substantive changes

hook_load_identity

# Log session end
if [[ -f "$PROJECT_DIR/scripts/utils/agent_log.sh" ]]; then
  source "$PROJECT_DIR/scripts/utils/agent_log.sh"
  agent_session_end "Session ended for $SESSION_USER"
fi


# --- Write per-user progress report ---
if [[ -n "$SESSION_USER" && "$SESSION_USER" != "unknown" ]]; then
  PROGRESS_DIR="$PROJECT_DIR/logs/progress/$SESSION_USER"
  mkdir -p "$PROGRESS_DIR"
  PROGRESS_FILE="$PROGRESS_DIR/$(date -u +%Y-%m-%d).md"
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
  echo "- Branch: $(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)" >> "$PROGRESS_FILE"
  echo "- Ended: $(date -u +%H:%M:%S)" >> "$PROGRESS_FILE"
fi

# --- Push logs/notes directly to main ---
if [[ -x "$PROJECT_DIR/scripts/utils/push-logs.sh" ]]; then
  bash "$PROJECT_DIR/scripts/utils/push-logs.sh" 2>/dev/null || true
fi

# --- Commit non-log changes on session branch ---
CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

if [[ "$CURRENT_BRANCH" == session/* ]]; then
  # Stage everything except logs/ and notes/ (those went to main)
  CHANGED="$(git -C "$PROJECT_DIR" status --porcelain -- ':!logs/' ':!notes/' 2>/dev/null | wc -l)"

  if [[ "$CHANGED" -gt 0 ]]; then
    git -C "$PROJECT_DIR" add -A -- ':!logs/' ':!notes/' 2>/dev/null || true
    git -C "$PROJECT_DIR" commit -m "Session work: ${SESSION_ID:-unknown}" 2>/dev/null || true
    GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" push -u origin "$CURRENT_BRANCH" 2>/dev/null || true

    # Create PR if gh is available
    if command -v gh &>/dev/null; then
      gh pr create \
        --title "Session: ${SESSION_ID:-unknown}" \
        --body "Automated session PR from $SESSION_USER" \
        --base main \
        --head "$CURRENT_BRANCH" 2>/dev/null || true
    fi
  fi
fi
