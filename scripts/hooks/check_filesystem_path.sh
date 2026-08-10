#!/bin/bash
set -euo pipefail

# Hook: check_filesystem_path.sh
# Trigger: PreToolUse → Write|Edit
# Purpose: Block writes outside approved paths
#
# Configure ALLOWED_PATHS in this script for your project.

# --- Resolve project dir ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"

# --- Source hook utilities ---
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || {
    # Minimal fallback if hook-utils not available
    hook_fail_open() { exit 0; }
    hook_block() { echo "{\"decision\":\"block\",\"reason\":\"$1\"}" | jq -c .; exit 2; }
    hook_silent() { exit 0; }
}

trap 'hook_fail_open "check_filesystem_path" "unexpected error"' ERR

# Additional roots to permit beyond the project itself. The project directory
# is always allowed (added below) — without that default this list is empty,
# and once the guard actually receives a path it would block every write to the
# project, including its own scripts. The guard's purpose is to stop writes
# OUTSIDE the project, not inside it.
ALLOWED_PATHS=(
    # Add extra allowed roots here, e.g.:
    # "/opt/data/"
)

# Always allow .claude config directories, and the per-session scratchpad the
# harness tells agents to use for temporary files. The scratchpad lives outside
# the project by design, so without this entry every scratch write is blocked
# the moment this guard starts working.
ALWAYS_ALLOWED=(
    "*/.claude/*"
    "/tmp/claude-*/*"
    "${TMPDIR:-/nonexistent}/*"
)

# Extract file_path from tool input (passed as JSON on stdin)
INPUT="$(cat)"

# The harness delivers {tool_name, tool_input:{file_path,...}}. This hook read
# .file_path from the TOP level, which is never populated in that shape, so
# FILE_PATH was always empty and the guard returned "not our concern" for every
# write. Accept the nested shape first, then the flat one for back-compat.
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .file_path // .path // empty' 2>/dev/null || echo "")"

# A payload we cannot parse must not silently disable the guard.
if ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    hook_fail_open "check_filesystem_path" "could not parse hook input as JSON"
fi

if [[ -z "$FILE_PATH" ]]; then
    hook_silent  # No file_path in input — not our concern
fi

# Check always-allowed patterns
for pattern in "${ALWAYS_ALLOWED[@]}"; do
    # shellcheck disable=SC2254
    if [[ "$FILE_PATH" == $pattern ]]; then
        hook_silent
    fi
done

# Always allow writes to log repo
hook_resolve_log_repo 2>/dev/null || true
if [[ -n "${LOG_REPO_DIR:-}" && "$FILE_PATH" == "${LOG_REPO_DIR}"* ]]; then
    hook_silent
fi

# The project directory is always an allowed write target.
ALLOWED_PATHS+=("$PROJECT_DIR")

# Check allowed paths (resolve relative entries against PROJECT_DIR)
for allowed in ${ALLOWED_PATHS[@]+"${ALLOWED_PATHS[@]}"}; do
    local_allowed="$allowed"
    [[ "$local_allowed" != /* ]] && local_allowed="${PROJECT_DIR}/${local_allowed}"
    if [[ "$FILE_PATH" == "${local_allowed}"* ]]; then
        hook_silent
    fi
done

hook_block "Write to ${FILE_PATH} is outside allowed paths. Allowed: ${ALLOWED_PATHS[*]}"
