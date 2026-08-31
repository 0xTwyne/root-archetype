#!/usr/bin/env bash
# validate_hook_syntax.sh — parse every hook and hook library with `bash -n`.
#
# Why this exists as its own gate: hook libraries are sourced by hooks that run
# on EVERY tool call. A syntax error in scripts/hooks/lib/*.sh does not fail one
# hook, it fails the PreToolUse gate, and the harness then refuses every Bash
# call — including the one you would use to fix the file. Recovery needs a tool
# that does not route through the broken hook.
#
# The break that motivated this: an apostrophe inside a comment inside a
# single-quoted jq program. The quote closed early, the rest of the comment
# parsed as shell, and the file stopped being loadable. `bash -n` catches it in
# a millisecond; nothing else in scripts/validate/ looks at shell syntax at all.
#
# Usage: scripts/validate/validate_hook_syntax.sh [--quiet]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Subshell around the fallback: without it, `||` binds only to the `cd` and the
# `&& pwd` runs after a SUCCESSFUL git call too, so REPO_ROOT becomes two paths
# separated by a newline and every later find silently matches nothing.
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd -- "$SCRIPT_DIR/../.." && pwd))"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

FAILED=0
CHECKED=0

while IFS= read -r -d '' f; do
  CHECKED=$((CHECKED + 1))
  if ! err="$(bash -n "$f" 2>&1)"; then
    FAILED=$((FAILED + 1))
    echo "SYNTAX ERROR: ${f#$REPO_ROOT/}" >&2
    echo "  $err" >&2
  fi
done < <(find "$REPO_ROOT/scripts" -type f -name '*.sh' -print0 | LC_ALL=C sort -z)

# Zero files checked means the search path is wrong, not that everything is fine.
if (( CHECKED == 0 )); then
  echo "Hook syntax validation FAILED: found no shell files under $REPO_ROOT/scripts" >&2
  exit 1
fi

if (( FAILED > 0 )); then
  echo "" >&2
  echo "Hook syntax validation FAILED: $FAILED of $CHECKED files do not parse." >&2
  echo "A library under scripts/hooks/lib/ that does not parse breaks every tool" >&2
  echo "call in the session. Fix it with an editor tool, not with Bash." >&2
  exit 1
fi

(( QUIET == 1 )) || echo "Hook syntax validation passed ($CHECKED shell files parse)"
