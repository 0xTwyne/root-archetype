#!/bin/bash
set -euo pipefail

# Skill usage measurement hook
# Triggered on PreToolUse for Skill tool
# Logs invocations for undertriggering/overtriggering analysis

# Resolve log repo for log directory
_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ -f "$_PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" ]]; then
    PROJECT_DIR="$_PROJECT_DIR"
    source "$_PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
    hook_resolve_log_repo 2>/dev/null || true
fi
LOG_DIR="${CLAUDE_PLUGIN_DATA:-${LOG_REPO_DIR:-$_PROJECT_DIR}/logs/skills}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/invocations.log"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Extract skill name from tool input (passed via stdin as JSON)
if [ -t 0 ]; then
    SKILL_NAME="unknown"
else
    INPUT=$(cat)
    SKILL_NAME=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Harness nests tool fields under tool_input; accept flat legacy shape.
    ti = data.get('tool_input') or {}
    print(ti.get('skill') or data.get('skill') or 'unknown')
except Exception as e:
    print('skill_usage_log: unparseable hook input: %s' % e, file=sys.stderr)
    print('unknown')
" || echo "unknown")
fi

echo "${TIMESTAMP} | ${SKILL_NAME}" >> "$LOG_FILE"
