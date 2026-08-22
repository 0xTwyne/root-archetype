#!/usr/bin/env bash
# Log repo resolution utility — sourced by hook-utils.sh.
# Resolves the log repo path from .archetype-manifest.json → repos/<name>.
#
# There is NO fallback to the root repo when the manifest declares a log repo.
# Logs, progress reports, notes, handoffs and the wiki all live in the log repo;
# root is not a degraded-mode destination for any of them, it is simply wrong.
# A "robustness" fallback here is worse than an error: writes to root succeed,
# nothing reports a problem, and the content drifts where nothing reads it.
#
# --- Resolve log repo path ---
# Sets LOG_REPO_DIR (exported) and returns 0 on success.
# On failure: leaves LOG_REPO_DIR unset, sets LOG_REPO_MISSING to the expected
# path, and returns 1. Idempotent — skips if already resolved.

# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

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
        LOG_REPO_DIR="$resolved"; export LOG_REPO_DIR
        unset LOG_REPO_MISSING
        return 0
      fi
      # Declared but absent. A broken setup, not single-repo mode.
      LOG_REPO_MISSING="$project_dir/repos/$log_name"; export LOG_REPO_MISSING
      unset LOG_REPO_DIR
      return 1
    fi
  fi

  # 3. No log repo declared — genuine single-repo mode, root is correct.
  LOG_REPO_DIR="$project_dir"; export LOG_REPO_DIR
  unset LOG_REPO_MISSING
  return 0
}

# --- Check if running in split mode ---
# Returns 0 (true) if log repo is separate from root repo.
# An unresolved log repo is not split mode — it is no mode at all.
hook_is_split_mode() {
  hook_resolve_log_repo || return 1
  [[ "$LOG_REPO_DIR" != "${PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-.}}" ]]
}

# --- Create per-user log directories ---
# Creates the standard directory tree in the log repo for a given user.
# Returns 1 without creating anything when the log repo is unresolved. Callers
# run under `set -e`, so invoke as `hook_ensure_log_dirs "$u" || true` where the
# caller intends to carry on and report the problem itself. Creating this tree
# somewhere else is never the right recovery: it is what makes a broken setup
# look healthy.
hook_ensure_log_dirs() {
  local user="${1:-${SESSION_USER:-unknown}}"
  hook_resolve_log_repo || return 1
  mkdir -p "$LOG_REPO_DIR/logs/audit/$user" \
           "$LOG_REPO_DIR/logs/progress/$user" \
           "$LOG_REPO_DIR/logs/skills" \
           "$LOG_REPO_DIR/notes/$user/plans" \
           "$LOG_REPO_DIR/notes/$user/handoffs/active" \
           "$LOG_REPO_DIR/notes/$user/handoffs/completed" \
           "$LOG_REPO_DIR/wiki" 2>/dev/null || true
}
