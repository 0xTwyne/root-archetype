#!/usr/bin/env bash
# update_hooks_lock.sh — regenerate HOOKS.lock from current scripts/hooks/ and
# scripts/validate/ contents.
#
# This is the explicit re-approval step. Run it ONLY after deliberately
# reviewing the changes — a drifted lock is meant to fail loudly until
# someone has looked at the diff. Commit the resulting HOOKS.lock alongside
# the hook/validator changes that motivated it.
#
# Usage:
#   scripts/validate/update_hooks_lock.sh
#   scripts/validate/update_hooks_lock.sh --check   # alias for validate_hooks_lock.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

if [[ "${1:-}" == "--check" ]]; then
  exec "$SCRIPT_DIR/validate_hooks_lock.sh" --diff
fi

LOCK_FILE="$REPO_ROOT/HOOKS.lock"

LOCK_ROOTS=(
  "scripts/hooks"
  "scripts/validate"
)
LOCK_EXCLUDES=(
  "scripts/hooks/lib/tools.lock"
)

cd "$REPO_ROOT"

find_args=()
for root in "${LOCK_ROOTS[@]}"; do
  [[ -d "$root" ]] && find_args+=("$root")
done
if (( ${#find_args[@]} == 0 )); then
  echo "update_hooks_lock: no locked roots found" >&2
  exit 1
fi

exclude_pattern=""
for ex in "${LOCK_EXCLUDES[@]}"; do
  if [[ -n "$exclude_pattern" ]]; then
    exclude_pattern+="|"
  fi
  exclude_pattern+="^${ex}$"
done

{
  echo "# HOOKS.lock — sha256 hashes of locked hook/validator files"
  echo "#"
  echo "# Locked roots: ${LOCK_ROOTS[*]}"
  echo "# Excluded:     ${LOCK_EXCLUDES[*]}"
  echo "#"
  echo "# Regenerated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# By:          scripts/validate/update_hooks_lock.sh"
  echo "#"
  echo "# A drifted lock means a hook or validator changed since last review."
  echo "# Run 'scripts/validate/validate_hooks_lock.sh --diff' to inspect drift."
  echo "# Re-run this script to acknowledge the changes after review."
  echo ""
  find "${find_args[@]}" -type f -print0 \
    | LC_ALL=C sort -z \
    | { if [[ -n "$exclude_pattern" ]]; then
          while IFS= read -r -d '' f; do
            if [[ ! "$f" =~ $exclude_pattern ]]; then
              printf '%s\0' "$f"
            fi
          done
        else
          cat
        fi
      } \
    | xargs -0 sha256sum
} > "$LOCK_FILE"

count="$(grep -cE '^[0-9a-f]{64} ' "$LOCK_FILE" || true)"
echo "update_hooks_lock: wrote $LOCK_FILE ($count files locked)"
