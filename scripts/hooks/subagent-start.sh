#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: SubagentStart
# 1. Injects repo-specific CLAUDE.md context when spawning agents for child repos
# 2. Injects session budget visibility (cost optimization)

REGISTRY="$PROJECT_DIR/agents/registry.json"

hook_load_identity

INPUT="$(cat)"
AGENT_TYPE="$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || echo "unknown")"
MODEL="$(echo "$INPUT" | jq -r '.tool_input.model // "default"' 2>/dev/null || echo "default")"

# Log subagent start
if [[ -f "$PROJECT_DIR/scripts/utils/agent_log.sh" ]]; then
  source "$PROJECT_DIR/scripts/utils/agent_log.sh"
  agent_observe "Subagent started" "type=$AGENT_TYPE model=$MODEL" 2>/dev/null || true
fi

# Look up agent in registry to find source repo
CONTEXT=""
if [[ -f "$REGISTRY" ]]; then
  SOURCE_REPO="$(jq -r --arg agent "$AGENT_TYPE" '
    (.agents // .)[] | select(.name == $agent) | .repo // .source_repo // empty
  ' "$REGISTRY" 2>/dev/null || echo "")"

  if [[ -n "$SOURCE_REPO" ]]; then
    # Find repo path from dependency map
    DEP_MAP="$PROJECT_DIR/.claude/dependency-map.json"
    REPO_PATH=""
    if [[ -f "$DEP_MAP" ]]; then
      REPO_PATH="$(jq -r --arg repo "$SOURCE_REPO" '.repos[$repo].path // empty' "$DEP_MAP" 2>/dev/null || echo "")"
    fi
    [[ -z "$REPO_PATH" ]] && REPO_PATH="$PROJECT_DIR/repos/$SOURCE_REPO"

    REPO_CLAUDE_MD="$REPO_PATH/CLAUDE.md"
    if [[ -f "$REPO_CLAUDE_MD" ]]; then
      CONTEXT="Repo context for $SOURCE_REPO (from $REPO_CLAUDE_MD):\n$(cat "$REPO_CLAUDE_MD")\n\nWorking directory: $REPO_PATH"
    else
      CONTEXT="Agent originates from repo: $SOURCE_REPO\nWorking directory: $REPO_PATH"
    fi
  fi
fi

# --- Budget visibility (cost optimization) ---
STATS_FILE="$PROJECT_DIR/.session-stats"
BUDGET_CTX=""
if [[ -f "$STATS_FILE" ]]; then
  TOOL_CALLS="$(jq -r '.tool_calls // 0' "$STATS_FILE" 2>/dev/null || echo "?")"
  SUBAGENTS="$(jq -r '.subagents // 0' "$STATS_FILE" 2>/dev/null || echo "?")"
  FILE_MODS="$(jq -r '.file_modifications // 0' "$STATS_FILE" 2>/dev/null || echo "?")"
  BUDGET_CTX="\n\nSESSION BUDGET: $TOOL_CALLS tool calls, $SUBAGENTS subagents, $FILE_MODS file modifications so far. Be efficient — prefer targeted searches over broad exploration. Complete your task in minimum turns."
fi

if [[ -n "$CONTEXT" ]]; then
  CONTEXT+="$BUDGET_CTX"
  jq -cn --arg ctx "$CONTEXT" '{"additionalContext": $ctx}'
elif [[ -n "$BUDGET_CTX" ]]; then
  jq -cn --arg ctx "$BUDGET_CTX" '{"additionalContext": $ctx}'
fi
