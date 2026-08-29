#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
# Fail open (exit 0) but say why — a silent `|| true` here previously left
# hook_load_identity undefined and killed the script under set -e.
if ! source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null; then
  echo "post-tool-use-audit: cannot source lib/hook-utils.sh — skipping audit" >&2
  exit 0
fi

set -euo pipefail

# Hook: PostToolUse (no matcher — fires for all tools)
# Categorizes tool usage, logs to audit trail, updates session stats.
# This is the cost-tracking backbone — every tool call is counted.

hook_load_identity

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "unknown")"

# --- Update session stats ---
STATS_FILE="$PROJECT_DIR/.session-stats"
if [[ -f "$STATS_FILE" ]]; then
  # Increment tool_calls
  TMP="$(jq '.tool_calls = (.tool_calls // 0) + 1' "$STATS_FILE" 2>/dev/null)" || TMP=""
  if [[ -n "$TMP" ]]; then
    # Track file modifications
    case "$TOOL_NAME" in
      Edit|Write|NotebookEdit)
        TMP="$(echo "$TMP" | jq '.file_modifications = (.file_modifications // 0) + 1')"
        ;;
      Agent)
        TMP="$(echo "$TMP" | jq '.subagents = (.subagents // 0) + 1')"
        ;;
    esac
    echo "$TMP" > "$STATS_FILE"
  fi
fi

# --- Append audit record ---
# Lands in the log repo (logs/audit/<user>/). There is NO root-repo fallback:
# audit entries written to the root repo exist in the log repo nowhere, which is
# exactly the four-month silent split this system already suffered once. If the
# log repo cannot be written, say so loudly and drop the record — a visible gap
# beats a trail that quietly forked. (In genuine single-repo mode, with no
# log_repo_name declared, LOG_REPO_DIR resolves to the root repo and writing
# there is correct.)
hook_resolve_log_repo "$PROJECT_DIR" 2>/dev/null || true

case "$TOOL_NAME" in
  Read|Glob|Grep)          CATEGORY="read" ;;
  Edit|Write|NotebookEdit) CATEGORY="modify" ;;
  Bash)                    CATEGORY="execute" ;;
  Agent|Task)              CATEGORY="delegate" ;;
  *)                       CATEGORY="other" ;;
esac

FILE_PATH="$(hook_extract_file_path "$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')")"

RECORD="$(jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg session "$SESSION_ID" \
  --arg user "$SESSION_USER" \
  --arg tool "$TOOL_NAME" \
  --arg cat "$CATEGORY" \
  --arg file "$FILE_PATH" \
  '{ts:$ts, session:$session, user:$user, tool:$tool, category:$cat}
   + (if $file != "" then {file:$file} else {} end)' 2>/dev/null)" || RECORD=""

if [[ -z "$RECORD" ]]; then
  echo "post-tool-use-audit: could not build audit record (jq failed)" >&2
  exit 0
fi

AUDIT_DIR="${LOG_REPO_DIR:-$PROJECT_DIR}/logs/audit/$SESSION_USER"
if ! { mkdir -p "$AUDIT_DIR" 2>/dev/null \
       && echo "$RECORD" >> "$AUDIT_DIR/tool-calls-$(date -u +%Y-%m-%d).jsonl" 2>/dev/null; }; then
  echo "post-tool-use-audit: could not write audit record under $AUDIT_DIR (check ownership/permissions) — record DROPPED, not redirected" >&2
  if declare -F agent_warn >/dev/null 2>&1; then
    agent_warn "post-tool-use-audit: audit write failed" "dir=$AUDIT_DIR tool=$TOOL_NAME" 2>/dev/null || true
  fi
fi

# Never blocks — exit 0 even when the audit write failed (diagnosed above)
exit 0
