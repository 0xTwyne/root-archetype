#!/usr/bin/env bash
# Shared hook utility library — sourced by all hooks for consistent behavior.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

# --- Fail-open exit ---
# Logs a warning and exits 0 (non-blocking). Use when a hook encounters
# an unexpected error and should degrade gracefully.
hook_fail_open() {
  local hook_name="${1:-unknown-hook}"
  local reason="${2:-unexpected error}"
  # Best-effort audit log — never fail on logging failure
  local project_dir="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)}"
  if [[ -f "$project_dir/scripts/utils/agent_log.sh" ]]; then
    source "$project_dir/scripts/utils/agent_log.sh" 2>/dev/null || true
    agent_warn "$hook_name: fail-open" "$reason" 2>/dev/null || true
  fi
  exit 0
}

# --- Hard block ---
# Emits a block decision and exits 2. Use for intentional policy enforcement.
hook_block() {
  local message="${1:?hook_block requires a message}"
  jq -cn --arg reason "$message" '{"decision":"block","reason":$reason}'
  exit 2
}

# --- Non-blocking warning ---
# Emits additionalContext and exits 0. Agent sees the warning but is not blocked.
hook_warn() {
  local context="${1:?hook_warn requires context}"
  jq -cn --arg ctx "$context" '{"additionalContext":$ctx}'
  exit 0
}

# --- Silent exit ---
# Exits 0 with no output. Use when the hook has nothing to report.
hook_silent() {
  exit 0
}

# --- Session-scoped deduplication ---
# Returns 0 on first call for a given scope-key per session, 1 on subsequent.
hook_dedup_check() {
  local scope_key="${1:?hook_dedup_check requires a scope-key}"
  local session_key="${SESSION_ID:-${PPID:-$$}}"
  local dedup_file="/tmp/archetype-hook-dedup-${session_key}-${scope_key}"

  if [[ -f "$dedup_file" ]]; then
    return 1  # Already fired this session
  fi
  touch "$dedup_file"
  return 0  # First time
}

# --- Timed deduplication ---
# Returns 0 if enough time has passed, 1 if still within TTL (seconds).
hook_timed_dedup() {
  local scope_key="${1:?hook_timed_dedup requires a scope-key}"
  local ttl_seconds="${2:?hook_timed_dedup requires ttl seconds}"
  local session_key="${SESSION_ID:-${PPID:-$$}}"
  local dedup_file="/tmp/archetype-hook-dedup-${session_key}-${scope_key}"

  if [[ -f "$dedup_file" ]]; then
    local now mtime
    now="$(date +%s)"
    mtime="$(stat -c %Y "$dedup_file" 2>/dev/null || echo 0)"
    if [[ $((now - mtime)) -lt "$ttl_seconds" ]]; then
      return 1
    fi
  fi
  touch "$dedup_file"
  return 0
}

# --- Extract repo name from a file path under repos/ ---
hook_extract_repo() {
  local file_path="${1:-}"
  echo "$file_path" | sed -n 's|.*/repos/\([^/]*\)/.*|\1|p'
}

# --- Extract file path from hook tool input JSON ---
hook_extract_file_path() {
  local tool_input="${1:-}"
  echo "$tool_input" | jq -r '.file_path // .path // empty' 2>/dev/null || echo ""
}

# --- Load session identity ---
# Sets SESSION_USER and SESSION_ID from .session-identity file.
hook_load_identity() {
  local project_dir="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)}"
  local identity_file="$project_dir/.session-identity"
  if [[ -f "$identity_file" ]]; then
    SESSION_USER="$(jq -r '.user // "unknown"' "$identity_file" 2>/dev/null || echo "unknown")"
    SESSION_ID="$(jq -r '.session_id // "unknown"' "$identity_file" 2>/dev/null || echo "unknown")"
  fi
  SESSION_USER="${SESSION_USER:-unknown}"
  SESSION_ID="${SESSION_ID:-unknown}"
}

# --- Inject facts cache into session context ---
# Emits additionalContext with notes/<user>/facts.md if present.
# Reads from log repo if available, falls back to project dir.
hook_inject_facts() {
  hook_load_identity
  hook_resolve_log_repo 2>/dev/null || true
  local base_dir="${LOG_REPO_DIR:-${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)}}"
  local facts_file="$base_dir/notes/$SESSION_USER/facts.md"
  if [[ -f "$facts_file" && -s "$facts_file" ]]; then
    local facts
    facts="$(cat "$facts_file" 2>/dev/null || true)"
    if [[ -n "$facts" ]]; then
      jq -cn --arg ctx "$facts" '{"additionalContext":$ctx}'
      return 0
    fi
  fi
  return 1
}

# --- Source log repo resolution utility ---
_HOOK_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_HOOK_LIB_DIR/log-repo.sh" ]]; then
  source "$_HOOK_LIB_DIR/log-repo.sh"
fi
