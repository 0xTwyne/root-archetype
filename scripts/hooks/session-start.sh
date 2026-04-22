#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: SessionStart
# 1. Resolves username and persists to .session-identity
# 2. Pulls latest main, creates session branch
# 3. Creates per-user log/notes directories (in log repo)
# 4. Loads agent registry + facts cache
# 5. Initializes session stats tracker

# Resolve log repo early (needed for dir creation and facts loading)
hook_resolve_log_repo 2>/dev/null || true

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

# Resolve project name from manifest or directory basename
ROOT_REPO_NAME="$(jq -r '.template_values.PROJECT_NAME // empty' "$PROJECT_DIR/.archetype-manifest.json" 2>/dev/null || echo "")"
[[ -z "$ROOT_REPO_NAME" ]] && ROOT_REPO_NAME="$(basename "$PROJECT_DIR")"

# Write .session-identity (gitignored) — read by all hooks
jq -cn \
  --arg session_id "$SESSION_ID" \
  --arg user "$SESSION_USER" \
  --arg branch "$BRANCH_NAME" \
  --arg root_repo "$ROOT_REPO_NAME" \
  --arg root_repo_path "$PROJECT_DIR" \
  --arg log_repo_path "${LOG_REPO_DIR:-$PROJECT_DIR}" \
  '{session_id: $session_id, user: $user, branch: $branch, root_repo: $root_repo, root_repo_path: $root_repo_path, log_repo_path: $log_repo_path}' \
  > "$PROJECT_DIR/.session-identity"

# --- Create per-user directories (in log repo) ---
hook_ensure_log_dirs "$SESSION_USER"

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

# --- Inject cross-session facts cache (from log repo) ---
FACTS_FILE="${LOG_REPO_DIR:-$PROJECT_DIR}/notes/$SESSION_USER/facts.md"
if [[ -f "$FACTS_FILE" ]] && [[ -s "$FACTS_FILE" ]]; then
  FACTS_LINES="$(wc -l < "$FACTS_FILE")"
  CONTEXT+="\nCROSS-SESSION FACTS ($FACTS_LINES lines loaded from notes/$SESSION_USER/facts.md):\n"
  CONTEXT+="$(cat "$FACTS_FILE")\n"
fi


# --- Guided init detection ---
if [[ -f "$PROJECT_DIR/.needs-init" ]]; then
  STEPS="$(jq -r '.steps_remaining | join(", ")' "$PROJECT_DIR/.needs-init" 2>/dev/null || echo "unknown")"
  CONTEXT+="This project needs initial setup. Remaining steps: $STEPS\n"
  CONTEXT+="Run the init-wizard skill to complete guided setup.\n"
fi

# --- Stale wiki detection (scan log repo sources) ---
if [[ -f "$PROJECT_DIR/knowledge/research/.last_compile" ]]; then
  _LOG_DIR="${LOG_REPO_DIR:-$PROJECT_DIR}"
  NEWEST_SOURCE="$(find "$_LOG_DIR/logs/progress" "$_LOG_DIR/notes" -name '*.md' -newer "$PROJECT_DIR/knowledge/research/.last_compile" 2>/dev/null | head -1)"
  if [[ -n "$NEWEST_SOURCE" ]]; then
    CONTEXT+="Knowledge base may be stale. Run /project-wiki compile to update.\n"
  fi
fi

# --- Structural invariant check ---
if [[ -x "$PROJECT_DIR/scripts/validate/validate_agents_structure.py" ]]; then
  if ! python3 "$PROJECT_DIR/scripts/validate/validate_agents_structure.py" &>/dev/null; then
    CONTEXT+="\nWARNING: Agent structure validation has failures. Run: python3 scripts/validate/validate_agents_structure.py\n"
  fi
fi

echo -e "$CONTEXT"
