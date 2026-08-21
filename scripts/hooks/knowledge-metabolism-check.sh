#!/usr/bin/env bash
set -euo pipefail

# Hook: SessionStart
#
# Checks whether the "knowledge metabolism" is alive — the loop that turns
# session output into retrievable knowledge:
#
#   session logs -> compile -> wiki article -> build-indexes -> recall hook
#
# Every stage is silent when it breaks. A stale INDEX.md still looks like an
# index; a missing STALENESS.md just means nothing reports as stale; a wiki
# nobody compiles into simply stops growing. This surfaces a one-line status,
# or names the broken stage.
#
# Reports (not blocks). Deduped to once an hour per session key.
#
# Disable with KNOWLEDGE_METABOLISM_CHECK=0.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
trap 'hook_fail_open "knowledge-metabolism-check" "unexpected error"' ERR

[[ "${KNOWLEDGE_METABOLISM_CHECK:-}" != "0" ]] || hook_silent
command -v jq &>/dev/null                       || hook_silent

hook_resolve_log_repo "$PROJECT_DIR" 2>/dev/null || true
KR="${LOG_REPO_DIR:-$PROJECT_DIR/repos/${LOG_REPO}}"
[[ -d "$KR" ]] || hook_silent

WIKI_DIR="$KR/wiki"
[[ -d "$WIKI_DIR" ]] || hook_silent

hook_timed_dedup "metabolism" 3600 || hook_silent

STALE_AFTER=$(( 7 * 24 * 3600 ))
NOW="$(date +%s)"
FAIL=""

file_age_ok() {
  local f="$1" mtime
  [[ -f "$f" ]] || return 1
  mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
  (( NOW - mtime < STALE_AFTER ))
}

# --- (a) there are articles at all ---
ARTICLE_COUNT="$(find "$WIKI_DIR" -name '*.md' \
  -not -name 'INDEX.md' -not -name 'STALENESS.md' \
  -not -name 'USAGE.md'  -not -name 'schema.md' \
  -not -name 'README.md' 2>/dev/null | wc -l)"
[[ "$ARTICLE_COUNT" -gt 0 ]] || FAIL="wiki has no articles yet — run /project-wiki compile"

# --- (b) INDEX.md exists and is not ancient ---
if [[ -z "$FAIL" ]]; then
  if [[ ! -f "$WIKI_DIR/INDEX.md" ]]; then
    FAIL="wiki/INDEX.md missing — run bash scripts/build-indexes.sh"
  elif ! file_age_ok "$WIKI_DIR/INDEX.md"; then
    FAIL="wiki/INDEX.md not rebuilt in over 7 days — run bash scripts/build-indexes.sh"
  fi
fi

# --- (c) STALENESS.md exists and is not ancient ---
if [[ -z "$FAIL" ]]; then
  if [[ ! -f "$WIKI_DIR/STALENESS.md" ]]; then
    FAIL="wiki/STALENESS.md missing — run bash scripts/build-indexes.sh"
  elif ! file_age_ok "$WIKI_DIR/STALENESS.md"; then
    FAIL="wiki/STALENESS.md not rebuilt in over 7 days — run bash scripts/build-indexes.sh"
  fi
fi

# --- (d) the index is not the known-degenerate output ---
# The old builder emitted `unknown/unknown.md` links for every article when
# frontmatter parsing failed. If that ever returns, say so loudly rather than
# letting a broken index masquerade as a working one.
if [[ -z "$FAIL" ]] && grep -q 'unknown/unknown\.md' "$WIKI_DIR/INDEX.md" 2>/dev/null; then
  FAIL="wiki/INDEX.md contains unknown/unknown.md links — frontmatter parsing is broken; check wiki/schema.md compliance"
fi

if [[ -n "$FAIL" ]]; then
  hook_warn "KNOWLEDGE METABOLISM STOPPED: ${FAIL}"
fi

# --- Healthy: one status line, with the stale count if any ---
# `grep -c` prints its count AND exits 1 when the count is zero. A `|| echo 0`
# fallback appends a second line ("0\n0") and breaks the arithmetic below;
# piping to `head` instead lets pipefail propagate grep's 1 and `set -e` kills
# the script silently. Swallow the status inside the substitution, then
# validate — both failure modes were hit here before this shape stuck.
STALE_COUNT="$(grep -c '^## \[' "$WIKI_DIR/STALENESS.md" 2>/dev/null || true)"
[[ "$STALE_COUNT" =~ ^[0-9]+$ ]] || STALE_COUNT=0

STATUS="Knowledge wiki: ${ARTICLE_COUNT} articles"
if [[ "$STALE_COUNT" -gt 0 ]]; then
  STATUS+=", ${STALE_COUNT} stale (see wiki/STALENESS.md; /project-wiki refresh to update)"
else
  STATUS+=", all fresh"
fi

# Recall backend, so a silent no-op retrieval hook is visible
if command -v colgrep &>/dev/null; then
  STATUS+=". Recall: colgrep."
elif command -v rg &>/dev/null; then
  STATUS+=". Recall: ripgrep."
else
  STATUS+=". Recall: DISABLED (needs ripgrep or colgrep)."
fi

hook_warn "$STATUS"
