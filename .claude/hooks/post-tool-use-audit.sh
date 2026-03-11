#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/.claude/hooks/lib/hook-utils.sh" 2>/dev/null || true

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

# Silent exit — this hook only updates state, never blocks or warns
exit 0
