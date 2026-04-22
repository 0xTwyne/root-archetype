#!/usr/bin/env bash
# Log repo resolution utility — sourced by hook-utils.sh.
# Resolves the log repo path from .archetype-manifest.json → repos/<name>.
# Falls back to $PROJECT_DIR if log repo is inaccessible (robustness only).

# --- Resolve log repo path ---
# Sets LOG_REPO_DIR (exported). Idempotent — skips if already set.
hook_resolve_log_repo() {
  # Already resolved this session
  if [[ -n "${LOG_REPO_DIR:-}" ]]; then return 0; fi

  # 1. Explicit env override
  if [[ -n "${ARCHETYPE_LOG_REPO:-}" && -d "$ARCHETYPE_LOG_REPO" ]]; then
    LOG_REPO_DIR="$ARCHETYPE_LOG_REPO"; export LOG_REPO_DIR; return 0
  fi

  # 2. Read log_repo_name from manifest → resolve via repos/ directory
  local project_dir="${1:-${PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}}"
  local manifest="$project_dir/.archetype-manifest.json"
  if [[ -f "$manifest" ]]; then
    local log_name
    log_name="$(jq -r '.log_repo_name // empty' "$manifest" 2>/dev/null || echo "")"
    if [[ -n "$log_name" ]]; then
      local repo_dir="$project_dir/repos/$log_name"
      # Handle both physical directories and symlinks (for externally-located log repos)
      if [[ -d "$repo_dir" ]]; then
        local resolved
        resolved="$(cd "$repo_dir" && pwd -P)"
        LOG_REPO_DIR="$resolved"; export LOG_REPO_DIR; return 0
      fi
    fi
  fi

  # 3. Fallback: write to root repo (pre-init or broken path)
  LOG_REPO_DIR="$project_dir"; export LOG_REPO_DIR; return 0
}

# --- Check if running in split mode ---
# Returns 0 (true) if log repo is separate from root repo.
hook_is_split_mode() {
  hook_resolve_log_repo
  [[ "$LOG_REPO_DIR" != "${PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" ]]
}

# --- Create per-user log directories ---
# Creates the standard directory tree in the log repo for a given user.
hook_ensure_log_dirs() {
  local user="${1:-${SESSION_USER:-unknown}}"
  hook_resolve_log_repo
  mkdir -p "$LOG_REPO_DIR/logs/audit/$user" \
           "$LOG_REPO_DIR/logs/progress/$user" \
           "$LOG_REPO_DIR/logs/skills" \
           "$LOG_REPO_DIR/notes/$user/plans" \
           "$LOG_REPO_DIR/notes/$user/handoffs/active" \
           "$LOG_REPO_DIR/notes/$user/handoffs/completed" \
           "$LOG_REPO_DIR/wiki" 2>/dev/null || true
}
