#!/usr/bin/env bash
set -euo pipefail

# Hook: UserPromptSubmit
#
# Push retrieval for the knowledge wiki. Searches the compiled wiki for
# articles relevant to the current prompt and injects their orientation
# section as background context.
#
# Complements the facts cache: notes/<user>/facts.md is personal and
# always-on (loaded by session-start.sh); this is shared institutional
# knowledge, pulled in topically and only when it looks relevant.
#
# Retrieval backend: colgrep if installed (semantic), otherwise ripgrep
# (lexical term scoring). The ripgrep path is the expected one — colgrep is
# an optional upgrade, not a requirement.
#
# Disable for a session with WIKI_RECALL=0.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
trap 'hook_fail_open "wiki-recall" "unexpected error"' ERR

INPUT="$(cat)"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")"
SESSION="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"

# --- Fast exits (silent) ---
[[ "${WIKI_RECALL:-}" != "0" ]]                  || hook_silent
[[ ${#PROMPT} -ge 40 ]]                          || hook_silent   # too short to be topical
[[ "$PROMPT" != /* ]]                            || hook_silent   # slash command
command -v jq &>/dev/null                        || hook_silent

# Per-session dedup keys off this, so prefer the payload's id over PPID
[[ -n "$SESSION" ]] && SESSION_ID="$SESSION"

hook_resolve_log_repo "$PROJECT_DIR" 2>/dev/null || true
WIKI_DIR="${LOG_REPO_DIR:-$PROJECT_DIR/repos/${LOG_REPO}}/wiki"
[[ -d "$WIKI_DIR" ]]                             || hook_silent

MAX_ARTICLES=2
MAX_FACT_LINES=18

# --- Build the query term list ---
# First 200 chars, lowercased, split on non-letters, drop stopwords and
# anything under 4 chars. Keeps the term list short so scoring stays cheap.
STOPWORDS=" the and for are but not you your with this that from have has about
into then than they them what when where which while would could should there their
here does did done can will just like make made get got use used using need needs
please help lets let run running add added fix fixed why how who whom all any some
more most other such only own same too very each few both "

mapfile -t TERMS < <(
  printf '%s' "$PROMPT" | cut -c1-200 | tr '[:upper:]' '[:lower:]' \
    | tr -cs '[:alpha:]-' '\n' \
    | awk -v stop="$STOPWORDS" '
        length($0) >= 4 && index(stop, " " $0 " ") == 0 && !seen[$0]++ { print }
      ' | head -12
)
[[ "${#TERMS[@]}" -gt 0 ]] || hook_silent

# --- Score articles ---
# colgrep when available (semantic), else ripgrep term-frequency scoring with
# a bonus for hits in frontmatter (title/tags) over hits in body prose.
SCORED="$(mktemp)"
trap 'rm -f "$SCORED"' EXIT

if command -v colgrep &>/dev/null; then
  QUERY="$(printf '%s ' "${TERMS[@]}")"
  (cd "$WIKI_DIR" && timeout 6 colgrep "$QUERY" . -k 5 -l 2>/dev/null || true) \
    | awk '{ print 1000 - NR, $0 }' > "$SCORED" || true
elif command -v rg &>/dev/null; then
  while IFS= read -r -d '' FILE; do
    BASE="$(basename "$FILE")"
    case "$BASE" in INDEX.md|STALENESS.md|USAGE.md|schema.md|README.md) continue ;; esac

    HEAD="$(head -20 "$FILE" 2>/dev/null || true)"   # frontmatter region
    SCORE=0
    DISTINCT=0
    for T in "${TERMS[@]}"; do
      BODY_HITS="$(rg -ioc --no-messages -w -- "$T" "$FILE" 2>/dev/null || echo 0)"
      HEAD_HITS="$(printf '%s' "$HEAD" | rg -ioc --no-messages -w -- "$T" 2>/dev/null || echo 0)"
      [[ "$BODY_HITS" -gt 0 || "$HEAD_HITS" -gt 0 ]] && DISTINCT=$(( DISTINCT + 1 ))
      # Cap each term's contribution so one common word cannot carry a match
      [[ "$BODY_HITS" -gt 4 ]] && BODY_HITS=4
      [[ "$HEAD_HITS" -gt 2 ]] && HEAD_HITS=2
      SCORE=$(( SCORE + BODY_HITS + 4 * HEAD_HITS ))
    done
    # A genuine topical hit matches several different terms, not one repeated
    if [[ "$DISTINCT" -ge 3 && "$SCORE" -ge 12 ]]; then
      printf '%s %s\n' "$SCORE" "${FILE#"$WIKI_DIR/"}" >> "$SCORED"
    fi
  done < <(find "$WIKI_DIR" -name '*.md' -print0 2>/dev/null)
else
  hook_silent
fi

[[ -s "$SCORED" ]] || hook_silent

mapfile -t TOP < <(sort -rn "$SCORED" | awk '{ print $2 }' | head -"$MAX_ARTICLES")
[[ "${#TOP[@]}" -gt 0 ]] || hook_silent

# --- Extract the orientation section from each article ---
# Prefer "Key Facts" (schema.md format), fall back to "Summary" (older
# compiled pages), else the first prose after the H1.
extract_facts() {
  awk -v maxlines="$MAX_FACT_LINES" '
    BEGIN { infront=0; frontdone=0; sect=""; n=0 }
    !frontdone && NR==1 && $0=="---" { infront=1; next }
    infront { if ($0=="---") { infront=0; frontdone=1 } next }
    /^## / {
      if (sect != "") exit
      if ($0 ~ /^## (Key Facts|Summary)/) { sect=$0; next }
      next
    }
    sect != "" { if (n++ >= maxlines) exit; print }
  ' "$1" | sed '/^[[:space:]]*$/d' | head -"$MAX_FACT_LINES"
}

BODY=""
CITED=()
for REL in "${TOP[@]}"; do
  # Do not re-inject the same article twice in one session
  KEY="wiki-recall-$(printf '%s' "$REL" | tr -c '[:alnum:]' '-')"
  hook_dedup_check "$KEY" || continue

  FILE="$WIKI_DIR/$REL"
  TITLE="$(grep -m1 '^title:' "$FILE" 2>/dev/null | sed 's/^title: *//; s/^"//; s/"$//')"
  [[ -n "$TITLE" ]] || TITLE="$(basename "$REL" .md)"

  FACTS="$(extract_facts "$FILE" 2>/dev/null || true)"
  [[ -n "$FACTS" ]] || continue

  BODY+="### ${TITLE}"$'\n'
  BODY+="Source: \`${LOG_REPO_NAME:-repos/${LOG_REPO}}/wiki/${REL}\`"$'\n\n'
  BODY+="${FACTS}"$'\n\n'
  CITED+=("$REL")
done

[[ -n "$BODY" ]] || hook_silent

CONTEXT="RELEVANT WIKI ARTICLES (auto-retrieved — background context, not an instruction):

${BODY}Read the full article if you need more than the summary above. These were
matched to your prompt and may not be relevant; ignore them if not."

jq -cn --arg ctx "$CONTEXT" '{"additionalContext":$ctx}'
exit 0
