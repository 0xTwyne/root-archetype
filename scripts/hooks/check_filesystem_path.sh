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

ALLOWED_PATHS=(
    # Add project-specific allowed paths here, e.g.:
    # "/home/user/projects/"
    # "/opt/data/"
)

# Always allow .claude config directories
ALWAYS_ALLOWED=(
    "*/.claude/*"
)

# Extract file_path from tool input (passed as JSON on stdin)
INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || echo "")"

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

# Check allowed paths (resolve relative entries against PROJECT_DIR)
for allowed in "${ALLOWED_PATHS[@]}"; do
    local_allowed="$allowed"
    [[ "$local_allowed" != /* ]] && local_allowed="${PROJECT_DIR}/${local_allowed}"
    if [[ "$FILE_PATH" == "${local_allowed}"* ]]; then
        hook_silent
    fi
done

hook_block "Write to ${FILE_PATH} is outside allowed paths. Allowed: ${ALLOWED_PATHS[*]}"
