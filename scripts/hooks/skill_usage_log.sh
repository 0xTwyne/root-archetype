#!/bin/bash
set -euo pipefail

# Skill usage measurement hook
# Triggered on PreToolUse for Skill tool
# Logs invocations for undertriggering/overtriggering analysis

LOG_DIR="${CLAUDE_PLUGIN_DATA:-logs/skills}"
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
