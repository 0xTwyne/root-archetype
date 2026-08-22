#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper — delegates to the knowledge repo's build-indexes.sh.
#
# All three generated indexes (progress, notes, wiki) live in the knowledge
# repo, so the knowledge repo owns its own indexing. This wrapper exists so
# callers in the governance root — push-logs.sh, the wrap-up skill — keep a
# stable path.
#
# Usage: bash scripts/build-indexes.sh


# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

LOG_REPO="knowledge"
if [[ -f "$PROJECT_DIR/.archetype-manifest.json" ]] && command -v jq &>/dev/null; then
  LOG_REPO="$(jq -r '.log_repo_name // "knowledge"' \
    "$PROJECT_DIR/.archetype-manifest.json" 2>/dev/null || echo "knowledge")"
fi

KNOWLEDGE_ROOT="$PROJECT_DIR/repos/$LOG_REPO"

if [[ ! -f "$KNOWLEDGE_ROOT/scripts/build-indexes.sh" ]]; then
  echo "build-indexes: $LOG_REPO repo not cloned, skipping" >&2
  exit 0
fi

bash "$KNOWLEDGE_ROOT/scripts/build-indexes.sh"
