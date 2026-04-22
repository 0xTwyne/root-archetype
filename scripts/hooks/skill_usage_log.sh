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
    # Tool input has 'skill' field
    print(data.get('tool_input', {}).get('skill', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
fi

echo "${TIMESTAMP} | ${SKILL_NAME}" >> "$LOG_FILE"
