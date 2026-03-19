#!/bin/bash
set -euo pipefail

# Scan staged git diff for secrets using shared pattern file.
# Exit 0 = clean, Exit 1 = secrets found.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../../..")"
PATTERNS_FILE="$REPO_ROOT/.claude/hooks/lib/secret-patterns.txt"

if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "WARN: Secret patterns file not found at $PATTERNS_FILE"
  echo "Skipping staged-diff secret scan."
  exit 0
fi

# Get staged diff
STAGED_DIFF="$(git diff --cached 2>/dev/null || true)"

if [[ -z "$STAGED_DIFF" ]]; then
  echo "No staged changes to scan."
  exit 0
fi

FOUND=0

while IFS=$'\t' read -r label regex _replacement; do
  # Skip comments and empty lines
  [[ -z "$label" || "$label" == \#* ]] && continue

  if echo "$STAGED_DIFF" | grep -qP "$regex"; then
    echo "SECRET DETECTED: $label"
    echo "  Pattern: $regex"
    echo "  Found in staged diff. Remove the secret before committing."
    echo ""
    FOUND=1
  fi
done < "$PATTERNS_FILE"

if [[ "$FOUND" -eq 1 ]]; then
  echo "FAIL: Secrets detected in staged changes. Unstage or remove them before committing."
  exit 1
else
  echo "OK: No secrets detected in staged diff."
  exit 0
fi
