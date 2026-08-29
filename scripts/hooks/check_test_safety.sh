#!/bin/bash
set -euo pipefail

# Hook: check_test_safety.sh
# Trigger: PreToolUse → Bash
# Purpose: Prevent unbounded test parallelism


# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

MAX_WORKERS="${TEST_MAX_WORKERS:-16}"

# Extract command from tool input
# Harness sends {tool_name, tool_input:{...}} on stdin; accept the legacy
# flat shape as fallback. Unparseable input fails open, but with a stderr
# diagnostic instead of silently.
INPUT="$(cat)"
if ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    echo "check_test_safety: could not parse hook input as JSON — allowing" >&2
    exit 0
fi
COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty')"

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Check for pytest with dangerous parallelism
if echo "$COMMAND" | grep -qE 'pytest.*-n\s+auto'; then
    echo "BLOCKED: 'pytest -n auto' would spawn unbounded workers."
    echo "Use 'pytest -n ${MAX_WORKERS}' or fewer."
    exit 2
fi

# Check for pytest -n N where N > MAX_WORKERS
if echo "$COMMAND" | grep -qP "pytest.*-n\s+(\d+)"; then
    # `|| true`: the enclosing test matches `-n\s+` (one or more spaces) while
    # this lookbehind is fixed-width and only matches one, so `pytest -n  4`
    # satisfies the `if` and finds nothing here -- grep exits 1, pipefail
    # promotes it, and the hook dies instead of blocking the run.
    # The `-n "$N"` test below already handles an empty result.
    N=$(echo "$COMMAND" | grep -oP -- "-n\s+\K\d+" | head -1 || true)
    if [[ -n "$N" && "$N" -gt "$MAX_WORKERS" ]]; then
        echo "BLOCKED: 'pytest -n ${N}' exceeds max workers (${MAX_WORKERS})."
        echo "Use 'pytest -n ${MAX_WORKERS}' or fewer."
        exit 2
    fi
fi

exit 0
