#!/bin/bash
set -euo pipefail

# Warn if current branch is main or master.
# Exit 0 = safe branch, Exit 2 = protected branch (warning, not error).

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

case "$BRANCH" in
  main|master)
    echo "WARNING: You are on the '$BRANCH' branch."
    echo "Consider creating a feature branch instead of committing directly."
    exit 2
    ;;
  unknown)
    echo "WARNING: Could not determine current branch."
    exit 2
    ;;
  *)
    echo "OK: On branch '$BRANCH'."
    exit 0
    ;;
esac
