#!/bin/bash
set -euo pipefail

# Session initialization script
# Sources agent logging and verifies environment

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"

REQUIRED_DIRS=(
    "${REPO_ROOT}/logs"
    "${REPO_ROOT}/notes"
)

# --- Dry-run / argv mode ---
# Print the resolved chain without side effects. No mkdir, no logging, no work.
#   session_init.sh --argv
if [[ "${1:-}" == "--argv" || "${1:-}" == "--dry-run" ]]; then
    echo "session_init.sh --argv (dry-run, no side effects)"
    echo "  script     : $0"
    echo "  repo_root  : $REPO_ROOT"
    echo "  agent_log  : ${REPO_ROOT}/scripts/utils/agent_log.sh"
    echo "  ensures    :"
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "               $dir (exists)"
        else
            echo "               $dir (would create)"
        fi
    done
    echo "  scans      : ${REPO_ROOT}/notes/*/handoffs/ for active handoffs"
    if [[ -f "${REPO_ROOT}/scripts/hooks/lib/hook-utils.sh" ]]; then
        # shellcheck disable=SC1091
        source "${REPO_ROOT}/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
        if declare -F hook_tools_audit >/dev/null 2>&1; then
            echo "  tools      :"
            hook_tools_audit | sed 's/^/               /'
        fi
    fi
    exit 0
fi

# Source agent logging
source "${REPO_ROOT}/scripts/utils/agent_log.sh"
agent_session_start "Session initialization"

echo "=== Session Init: $(basename "$REPO_ROOT") ==="

# --- Verify required directories ---
for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        echo "Created: $dir"
    fi
done

# --- Check active handoffs ---
ACTIVE_COUNT=$(find "${REPO_ROOT}/notes" -path "*/handoffs/*.md" -not -path "*/completed/*" -not -name "INDEX.md" 2>/dev/null | wc -l)
echo "Active handoffs: ${ACTIVE_COUNT}"

# --- Health summary ---
echo ""
echo "Session ready."
agent_task_end "Session initialization" "success"
