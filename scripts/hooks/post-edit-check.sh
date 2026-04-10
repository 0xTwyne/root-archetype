#!/usr/bin/env bash
set -euo pipefail

# Hook: PostToolUse (matcher: Edit|Write)
# Ripple detection + write-time linting for child repos

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
DEP_MAP="$PROJECT_DIR/.claude/dependency-map.json"
TOOLCHAINS="$PROJECT_DIR/.claude/repo-toolchains.json"

source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
trap 'hook_fail_open "post-edit-check" "unexpected error"' ERR

INPUT="$(cat)"
TOOL_INPUT="$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null || echo "{}")"
FILE_PATH="$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || echo "")"

# Only process files in registered repos
REPO_NAME="$(hook_extract_repo "$FILE_PATH")"
[[ -n "$REPO_NAME" ]] || hook_silent

CONTEXT=""
add_context() {
  if [[ -n "$CONTEXT" ]]; then CONTEXT+=$'\n\n'; fi
  CONTEXT+="$1"
}

# --- Ripple detection ---
if [[ -f "$DEP_MAP" ]]; then
  DOWNSTREAM="$(jq -r --arg repo "$REPO_NAME" '
    [.edges[] | select(.from == $repo) |
     "- **" + .to + "** (" + (.coupling | if type == "array" then join(", ") else . end) + ")"]
    | join("\n")' "$DEP_MAP" 2>/dev/null || echo "")"

  if [[ -n "$DOWNSTREAM" && "$DOWNSTREAM" != "null" ]]; then
    if hook_dedup_check "ripple-${REPO_NAME}"; then
      add_context "RIPPLE WARNING: You modified a file in $REPO_NAME which is an upstream dependency. Changes here may affect:\n$DOWNSTREAM\nVerify downstream repos are not broken by this change."
    fi
  fi
fi

# --- Write-time linting ---
if [[ -f "$TOOLCHAINS" ]]; then
  FILE_EXT=".${FILE_PATH##*.}"
  REPO_CONFIG="$(jq -r --arg repo "$REPO_NAME" '.[$repo] // empty' "$TOOLCHAINS" 2>/dev/null || echo "")"

  if [[ -n "$REPO_CONFIG" && "$REPO_CONFIG" != "null" ]]; then
    MATCHES="$(echo "$REPO_CONFIG" | jq -r --arg ext "$FILE_EXT" '
      .patterns // [] | map(select(endswith($ext))) | length > 0' 2>/dev/null || echo "false")"

    if [[ "$MATCHES" == "true" ]]; then
      REPO_DIR="$(jq -r --arg repo "$REPO_NAME" '.repos[$repo].path // empty' "$DEP_MAP" 2>/dev/null || echo "")"
      [[ -d "$REPO_DIR" ]] || REPO_DIR="$PROJECT_DIR/repos/$REPO_NAME"
      REPO_REL_PATH="${FILE_PATH#*$REPO_NAME/}"
      ISSUES=""

      FORMATTER_CHECK="$(echo "$REPO_CONFIG" | jq -r '.formatter_check // empty' 2>/dev/null || echo "")"
      if [[ -n "$FORMATTER_CHECK" && -d "$REPO_DIR" ]]; then
        FMT_OUTPUT="$(cd "$REPO_DIR" && eval "$FORMATTER_CHECK $REPO_REL_PATH" 2>&1 | head -10)" || true
        if echo "$FMT_OUTPUT" | grep -qiE 'would reformat|error|diff|warning' 2>/dev/null; then
          ISSUES+="FORMAT: $FMT_OUTPUT\n"
        fi
      fi

      LINTER="$(echo "$REPO_CONFIG" | jq -r '.linter // empty' 2>/dev/null || echo "")"
      if [[ -n "$LINTER" && -d "$REPO_DIR" ]]; then
        LINT_OUTPUT="$(cd "$REPO_DIR" && eval "$LINTER $REPO_REL_PATH" 2>&1 | head -10)" || true
        if echo "$LINT_OUTPUT" | grep -qiE 'error|warning|violation|found' 2>/dev/null; then
          ISSUES+="LINT: $LINT_OUTPUT\n"
        fi
      fi

      if [[ -n "$ISSUES" ]]; then
        source "$PROJECT_DIR/scripts/hooks/lib/session-counters.sh"
        EDIT_COUNT="$(session_counter_increment "lint-$REPO_NAME")"
        add_context "LINT WARNING in $REPO_REL_PATH:\n$ISSUES\nFix ALL lint/format violations in files you touch."
      fi
    fi
  fi
fi

if [[ -n "$CONTEXT" ]]; then
  hook_warn "$CONTEXT"
fi

hook_silent
