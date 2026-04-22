#!/usr/bin/env bash
set -euo pipefail

# Hook: PreToolUse (matcher: "Edit|Write")
# Merged guard: secret scan → log isolation → config tamper-proofing

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
PATTERNS_FILE="$PROJECT_DIR/scripts/hooks/lib/secret-patterns.txt"
MAINTAINERS_FILE="$PROJECT_DIR/MAINTAINERS.json"

source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
hook_resolve_log_repo 2>/dev/null || true
trap 'hook_fail_open "pre-edit-guard" "unexpected error"' ERR

INPUT="$(cat)"
TOOL_INPUT="$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null || echo "{}")"
FILE_PATH="$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || echo "")"
CONTENT="$(echo "$TOOL_INPUT" | jq -r '.content // .new_string // empty' 2>/dev/null || echo "")"

if [[ -z "$FILE_PATH" ]]; then
  hook_silent
fi

CONTEXT=""
add_context() {
  if [[ -n "$CONTEXT" ]]; then CONTEXT+=$'\n\n'; fi
  CONTEXT+="$1"
}

# --- Secret scan ---
if [[ -n "$CONTENT" && -f "$PATTERNS_FILE" ]]; then
  while IFS=$'\t' read -r label regex replacement; do
    [[ -z "$label" || -z "$regex" ]] && continue
    [[ "$label" == \#* ]] && continue
    if echo "$CONTENT" | grep -qE "$regex"; then
      hook_block "Secret detected in file content. Pattern: $label. Target: $FILE_PATH. NEVER write secrets to tracked files."
    fi
  done < "$PATTERNS_FILE"
fi

# --- Log isolation (applies to paths in both root repo and log repo) ---
REL_PATH=""
IS_LOG_PATH=false

# Check if path is in the log repo
_LOG_DIR="${LOG_REPO_DIR:-$PROJECT_DIR}"
if [[ "$_LOG_DIR" != "$PROJECT_DIR" && "$FILE_PATH" == "$_LOG_DIR"/* ]]; then
  REL_PATH="${FILE_PATH#$_LOG_DIR/}"
elif [[ "$FILE_PATH" == "$PROJECT_DIR"/* ]]; then
  REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
fi

if [[ -n "$REL_PATH" ]]; then
  case "$REL_PATH" in
    logs/audit/*|logs/progress/*|notes/*)
      IS_LOG_PATH=true
      ;;
  esac
fi

if [[ "$IS_LOG_PATH" == "true" ]]; then
  # Exempt shared files
  case "$REL_PATH" in
    logs/progress/INDEX.md|notes/handoffs/*|notes/INDEX.md|notes/agent-changelog.md)
      IS_LOG_PATH=false
      ;;
  esac
  [[ "$(basename "$REL_PATH")" == ".gitkeep" ]] && IS_LOG_PATH=false

  # In split mode, warn if writing to root repo's skeletal stubs
  if [[ "$IS_LOG_PATH" == "true" && "$_LOG_DIR" != "$PROJECT_DIR" && "$FILE_PATH" == "$PROJECT_DIR"/* ]]; then
    add_context "WARNING: logs/ and notes/ in the root repo are stubs. Actual data should be written to the log repo at ${_LOG_DIR}."
  fi
fi

if [[ "$IS_LOG_PATH" == "true" ]]; then
  hook_load_identity
  if [[ "$SESSION_USER" != "unknown" ]]; then
    TARGET_USER=""
    case "$REL_PATH" in
      logs/audit/*) TARGET_USER="$(echo "$REL_PATH" | cut -d/ -f3)" ;;
      logs/progress/*) TARGET_USER="$(echo "$REL_PATH" | cut -d/ -f3)" ;;
      notes/*) TARGET_USER="$(echo "$REL_PATH" | cut -d/ -f2)" ;;
    esac

    if [[ -n "$TARGET_USER" && "$TARGET_USER" != "$SESSION_USER" ]]; then
      hook_block "BLOCKED: Cross-user write denied. Path targets \"$TARGET_USER\" but session belongs to \"$SESSION_USER\". File: $REL_PATH"
    fi
  fi
fi

# --- Config tamper-proofing ---
if [[ ! -f "$MAINTAINERS_FILE" ]]; then
  if [[ -n "$CONTEXT" ]]; then hook_warn "$CONTEXT"; fi
  hook_silent
fi

REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
USER_EMAIL="$(git config user.email 2>/dev/null || echo "")"

IS_CORE=false
# .claude/* and CLAUDE.md are generated (gitignored) but still protected at runtime
case "$REL_PATH" in
  .claude/*|CLAUDE.md|scripts/*|docs/*)
    IS_CORE=true
    ;;
esac

if [[ "$IS_CORE" == "true" ]]; then
  # Check if user is a maintainer
  IS_MAINTAINER="$(jq -r --arg email "$USER_EMAIL" '
    (.global // []) | map(select(. == $email)) | length > 0' "$MAINTAINERS_FILE" 2>/dev/null || echo "false")"

  if [[ "$IS_MAINTAINER" == "true" ]]; then
    if [[ -n "$CONTEXT" ]]; then hook_warn "$CONTEXT"; fi
    hook_silent
  fi

  # Hard-block behavioral config files for non-maintainers
  IS_HARD_BLOCK=false
  case "$REL_PATH" in
    CLAUDE.md|.claude/settings.json|.claude/settings.local.json|scripts/hooks/*|.claude/agents/*)
      IS_HARD_BLOCK=true
      ;;
  esac

  MAINTAINER_LIST="$(jq -r '(.global // []) | join(", ")' "$MAINTAINERS_FILE" 2>/dev/null || echo "unknown")"

  if [[ "$IS_HARD_BLOCK" == "true" ]]; then
    hook_block "BLOCKED: $REL_PATH is a protected config file maintained by $MAINTAINER_LIST. Submit changes via PR."
  fi

  add_context "WARNING: You are editing a core file maintained by $MAINTAINER_LIST. Changes on session branch will be included in auto-PR at session end."
fi

if [[ -n "$CONTEXT" ]]; then
  hook_warn "$CONTEXT"
fi

hook_silent
