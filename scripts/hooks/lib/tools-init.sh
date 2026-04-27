#!/usr/bin/env bash
# tools-init.sh — generate scripts/hooks/lib/tools.lock from currently-resolved tools.
#
# Treat invocation as a security event: review the resulting tools.lock before
# trusting hooks again. Re-run after deliberate environment changes (package
# upgrades, new tooling) — never silently.
#
# Usage:
#   scripts/hooks/lib/tools-init.sh           # generate / refresh tools.lock
#   scripts/hooks/lib/tools-init.sh --diff    # show what would change, no write
#   scripts/hooks/lib/tools-init.sh --strict  # fail if any declared tool is missing

set -euo pipefail

LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE="$LIB_DIR/tools.lock.example"
LOCK="$LIB_DIR/tools.lock"

MODE="write"
STRICT=0
for arg in "$@"; do
  case "$arg" in
    --diff)   MODE="diff" ;;
    --strict) STRICT=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "tools-init: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$EXAMPLE" ]]; then
  echo "tools-init: missing template: $EXAMPLE" >&2
  exit 1
fi

declared_tools=()
while IFS=$'\t' read -r name _; do
  [[ -z "$name" || "$name" =~ ^# ]] && continue
  declared_tools+=("$name")
done < "$EXAMPLE"

generated=""
generated+="# tools.lock — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"$'\n'
generated+="# DO NOT EDIT BY HAND. Re-run scripts/hooks/lib/tools-init.sh after deliberate"$'\n'
generated+="# environment changes. This file is gitignored."$'\n'

missing=()
for name in "${declared_tools[@]}"; do
  resolved="$(command -v "$name" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    missing+=("$name")
    generated+="# MISSING: $name (not on PATH at init time)"$'\n'
    continue
  fi
  real="$(readlink -f "$resolved" 2>/dev/null || echo "$resolved")"
  generated+="${name}"$'\t'"${real}"$'\n'
done

if [[ "$MODE" == "diff" ]]; then
  if [[ -f "$LOCK" ]]; then
    diff -u "$LOCK" <(printf '%s' "$generated") || true
  else
    echo "(no existing tools.lock — would create:)"
    printf '%s' "$generated"
  fi
else
  printf '%s' "$generated" > "$LOCK"
  pinned_count="$(grep -cE '^[^#[:space:]]' "$LOCK" || true)"
  echo "tools-init: wrote $LOCK ($pinned_count tools pinned)"
fi

if (( ${#missing[@]} > 0 )); then
  echo "tools-init: WARNING: missing tools: ${missing[*]}" >&2
  if (( STRICT )); then
    exit 3
  fi
fi
