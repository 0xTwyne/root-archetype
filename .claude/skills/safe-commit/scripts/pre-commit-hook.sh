#!/bin/bash
set -euo pipefail

# On-demand PreToolUse hook for safe-commit skill.
# Intercepts `git commit` commands to run staged-diff secret scanning
# and branch protection checks before the commit proceeds.
#
# This is a DEMONSTRATION of the on-demand hook pattern:
# - Registered in .claude/settings.json as a PreToolUse hook on Bash
# - Only activates when the command contains "git commit"
# - Composes with (does not duplicate) existing always-on hooks
#
# To enable:  Add to .claude/settings.json PreToolUse hooks
# To disable: Remove from .claude/settings.json PreToolUse hooks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read the tool input from stdin (Claude Code passes JSON)
INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('command',''))" 2>/dev/null || echo "")"

# Only intercept git commit commands
if ! echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
  exit 0
fi

# --- Check 1: Scan staged diff for secrets ---
SCAN_RESULT="$(bash "$SCRIPT_DIR/scan-staged.sh" 2>&1)" || {
  echo "BLOCKED by safe-commit: secrets detected in staged changes"
  echo ""
  echo "$SCAN_RESULT"
  echo ""
  echo "Remove secrets from staged files before committing."
  exit 2
}

# --- Check 2: Branch protection warning ---
BRANCH_RESULT="$(bash "$SCRIPT_DIR/check-branch.sh" 2>&1)"
BRANCH_EXIT=$?
if [[ $BRANCH_EXIT -eq 2 ]]; then
  # Warning only — don't block, just inform
  echo "$BRANCH_RESULT"
  echo "(Proceeding — this is a warning, not a block)"
  echo ""
fi

exit 0
