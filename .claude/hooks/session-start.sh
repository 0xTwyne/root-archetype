#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/.claude/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: SessionStart
# 1. Resolves username and persists to .session-identity
# 2. Pulls latest main, creates session branch
# 3. Creates per-user log/notes directories
# 4. Loads agent registry + facts cache
# 5. Initializes session stats tracker

INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="ses_$(date -u +%Y%m%d_%H%M%S)_$$"
fi

SHORT_SESSION="$(echo "$SESSION_ID" | head -c 12)"
DATE_TAG="$(date -u +%Y-%m-%d)"
BRANCH_NAME="session/${SHORT_SESSION}_${DATE_TAG}"

# --- Resolve username ---
SESSION_USER=""

# 1. Try GitHub CLI
if [[ -z "$SESSION_USER" ]] && command -v gh &>/dev/null; then
  SESSION_USER="$(gh api user --jq '.login' 2>/dev/null || echo "")"
fi

# 2. Try git config
if [[ -z "$SESSION_USER" ]]; then
  SESSION_USER="$(git config user.name 2>/dev/null || echo "")"
fi

# 3. Try $USER env var
if [[ -z "$SESSION_USER" ]]; then
  SESSION_USER="${USER:-}"
fi

# 4. Absolute fallback
if [[ -z "$SESSION_USER" ]]; then
  SESSION_USER="unknown"
fi

# Sanitize to [a-zA-Z0-9_-]
SESSION_USER="$(echo "$SESSION_USER" | tr -cd 'a-zA-Z0-9_-')"
[[ -z "$SESSION_USER" ]] && SESSION_USER="unknown"

# Write .session-identity (gitignored) — read by all hooks
jq -cn \
  --arg session_id "$SESSION_ID" \
  --arg user "$SESSION_USER" \
  --arg branch "$BRANCH_NAME" \
  '{session_id: $session_id, user: $user, branch: $branch}' \
  > "$PROJECT_DIR/.session-identity"

# --- Create per-user directories ---
mkdir -p "$PROJECT_DIR/logs/audit/$SESSION_USER"
mkdir -p "$PROJECT_DIR/logs/progress/$SESSION_USER"
mkdir -p "$PROJECT_DIR/notes/$SESSION_USER/plans"

# Initialize session stats tracker (gitignored)
echo '{"tool_calls":0,"subagents":0,"file_modifications":0}' > "$PROJECT_DIR/.session-stats"

# --- Pull latest main before branching ---
CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
PULL_STATUS=""
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  if GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" pull --ff-only origin main 2>/dev/null; then
    PULL_STATUS="main updated"
  else
    PULL_STATUS="pull failed (may have local changes)"
  fi
else
  GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" fetch origin main 2>/dev/null || true
  PULL_STATUS="fetched origin/main"
fi

# Create session branch
if [[ "$CURRENT_BRANCH" != "$BRANCH_NAME" ]]; then
  git -C "$PROJECT_DIR" checkout -b "$BRANCH_NAME" 2>/dev/null || true
fi

# Log session start
if [[ -f "$PROJECT_DIR/scripts/utils/agent_log.sh" ]]; then
  source "$PROJECT_DIR/scripts/utils/agent_log.sh"
  agent_session_start "Session started by $SESSION_USER on branch $BRANCH_NAME"
fi

# --- Build context output ---
CONTEXT="Session branch: $BRANCH_NAME\nUser: $SESSION_USER\nAudit logging: active (logs/audit/$SESSION_USER/)\n"

# Agent registry summary
if [[ -f "$PROJECT_DIR/agents/registry.json" ]]; then
  AGENT_COUNT="$(jq 'length // (.agents | length) // 0' "$PROJECT_DIR/agents/registry.json" 2>/dev/null || echo "0")"
  CONTEXT+="Agent registry: $AGENT_COUNT agents available.\n"
fi

# --- Inject cross-session facts cache ---
FACTS_FILE="$PROJECT_DIR/notes/$SESSION_USER/facts.md"
if [[ -f "$FACTS_FILE" ]] && [[ -s "$FACTS_FILE" ]]; then
  FACTS_LINES="$(wc -l < "$FACTS_FILE")"
  CONTEXT+="\nCROSS-SESSION FACTS ($FACTS_LINES lines loaded from notes/$SESSION_USER/facts.md):\n"
  CONTEXT+="$(cat "$FACTS_FILE")\n"
fi

# --- Check registered repos for agent diffs ---
DEP_MAP="$PROJECT_DIR/.claude/dependency-map.json"
AGENT_DIFFS=""
if [[ -f "$DEP_MAP" ]]; then
  while IFS='|' read -r name path; do
    [[ -d "$path/.git" ]] || continue
    GIT_TERMINAL_PROMPT=0 git -C "$path" fetch origin main 2>/dev/null || continue
    DIFF_FILES="$(git -C "$path" diff --name-only HEAD..origin/main -- "CLAUDE.md" ".claude/" 2>/dev/null || true)"
    if [[ -n "$DIFF_FILES" ]]; then
      while IFS= read -r df; do
        [[ -z "$df" ]] && continue
        AGENT_DIFFS+="  - [$name] $df (remote has updates)\n"
      done <<< "$DIFF_FILES"
    fi
  done < <(jq -r '.repos | to_entries[] | "\(.key)|\(.value.path)"' "$DEP_MAP" 2>/dev/null || true)
fi

if [[ -n "$AGENT_DIFFS" ]]; then
  CONTEXT+="\nAGENT FILE UPDATES on remote:\n$AGENT_DIFFS"
fi

# --- Structural invariant check ---
if [[ -x "$PROJECT_DIR/scripts/validate/validate_agents_structure.py" ]]; then
  if ! python3 "$PROJECT_DIR/scripts/validate/validate_agents_structure.py" &>/dev/null; then
    CONTEXT+="\nWARNING: Agent structure validation has failures. Run: python3 scripts/validate/validate_agents_structure.py\n"
  fi
fi

echo -e "$CONTEXT"
