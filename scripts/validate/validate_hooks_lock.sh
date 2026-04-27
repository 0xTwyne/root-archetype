#!/usr/bin/env bash
# validate_hooks_lock.sh — verify scripts/hooks/ and scripts/validate/ haven't drifted
# from HOOKS.lock.
#
# Treat hook/validator changes as security events: a fork or child repo that
# silently mutates a hook can defeat the gate it implements. This script
# computes a deterministic hash over the locked file tree and compares to
# HOOKS.lock. Any drift exits non-zero.
#
# Usage:
#   scripts/validate/validate_hooks_lock.sh           # exit 0 if clean, 1 if drifted
#   scripts/validate/validate_hooks_lock.sh --diff    # show drifted files
#
# Acknowledged updates: scripts/validate/update_hooks_lock.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -z "$REPO_ROOT" ]] && REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LOCK_FILE="$REPO_ROOT/HOOKS.lock"

DIFF_MODE=0
[[ "${1:-}" == "--diff" ]] && DIFF_MODE=1

# Locked roots — hashes cover every file under these directories.
LOCK_ROOTS=(
  "scripts/hooks"
  "scripts/validate"
)

# Files under LOCK_ROOTS that are EXCLUDED from the hash (per-installation,
# generated, or otherwise variable).
LOCK_EXCLUDES=(
  "scripts/hooks/lib/tools.lock"
)

_compute_hashes() {
  cd "$REPO_ROOT"
  local find_args=()
  local root
  for root in "${LOCK_ROOTS[@]}"; do
    [[ -d "$root" ]] && find_args+=("$root")
  done
  if (( ${#find_args[@]} == 0 )); then
    echo "validate_hooks_lock: no locked roots found under $REPO_ROOT" >&2
    return 1
  fi

  local exclude_pattern=""
  local ex
  for ex in "${LOCK_EXCLUDES[@]}"; do
    if [[ -n "$exclude_pattern" ]]; then
      exclude_pattern+="|"
    fi
    exclude_pattern+="^${ex}$"
  done

  # Deterministic: sort by path, hash each file, prepend with relative path.
  find "${find_args[@]}" -type f -print0 \
    | LC_ALL=C sort -z \
    | { if [[ -n "$exclude_pattern" ]]; then
          # Filter out excluded paths (NUL-delimited).
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
}

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "validate_hooks_lock: HOOKS.lock missing — run scripts/validate/update_hooks_lock.sh to create it" >&2
  exit 1
fi

actual="$(_compute_hashes)"
expected="$(grep -vE '^(#|[[:space:]]*$)' "$LOCK_FILE" || true)"

if [[ "$actual" == "$expected" ]]; then
  echo "validate_hooks_lock: OK ($(printf '%s\n' "$actual" | wc -l) files match)"
  exit 0
fi

echo "validate_hooks_lock: DRIFT detected" >&2
if (( DIFF_MODE )); then
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
  echo
  echo "To accept these changes (security event): scripts/validate/update_hooks_lock.sh" >&2
fi
exit 1
