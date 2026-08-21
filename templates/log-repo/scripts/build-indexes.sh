#!/usr/bin/env bash
set -euo pipefail

# Rebuilds all auto-generated indexes, all of which live in this repo:
#   1. Progress report index  → logs/progress/INDEX.md
#   2. Notes index            → notes/INDEX.md
#   3. Wiki index + staleness → wiki/INDEX.md, wiki/STALENESS.md
#
# This repo owns its own indexing. The governance root calls it through the
# thin wrapper at <root>/scripts/build-indexes.sh, which is also what
# push-logs.sh invokes before commit.
#
# Usage: bash scripts/build-indexes.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Governance root — frontmatter `sources:` paths are relative to it, so
# staleness resolves them from here.
PROJECT_ROOT="$(cd -- "$KNOWLEDGE_ROOT/../.." 2>/dev/null && pwd || echo "$KNOWLEDGE_ROOT")"

if [[ ! -d "$KNOWLEDGE_ROOT/.git" ]]; then
  echo "build-indexes: knowledge repo has no .git, skipping" >&2
  exit 0
fi

# =============================================================================
# 1. Progress Report Index
# =============================================================================

build_progress_index() {
  local PROGRESS_DIR="$KNOWLEDGE_ROOT/logs/progress"
  local OUTPUT="$PROGRESS_DIR/INDEX.md"
  local RECENT_DAYS=14
  local CUTOFF_DATE
  CUTOFF_DATE="$(date -u -d "$RECENT_DAYS days ago" +%Y-%m-%d 2>/dev/null \
    || date -u -v-${RECENT_DAYS}d +%Y-%m-%d)"

  local ALL_REPORTS=()
  while IFS= read -r -d '' FILE; do
    ALL_REPORTS+=("$FILE")
  done < <(find "$PROGRESS_DIR" -name '*.md' -not -name 'INDEX.md' -print0 2>/dev/null || true)

  [[ ${#ALL_REPORTS[@]} -eq 0 ]] && return 0

  declare -a ENTRIES=()
  for REPORT in "${ALL_REPORTS[@]}"; do
    local BASENAME USER DATE SUMMARY=""
    BASENAME="$(basename "$REPORT")"
    USER="$(basename "$(dirname "$REPORT")")"
    DATE="${BASENAME%%_*}"
    DATE="${DATE%.md}"

    local IN_SUMMARY=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^##\ Wrap-up ]]; then IN_SUMMARY=true; continue; fi
      if [[ "$IN_SUMMARY" == true ]]; then
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^## ]] && break
        SUMMARY="$line"; break
      fi
    done < "$REPORT"
    if [[ -z "$SUMMARY" ]]; then
      while IFS= read -r line; do
        if [[ "$line" =~ ^###\ What\ was\ done ]]; then IN_SUMMARY=true; continue; fi
        if [[ "$IN_SUMMARY" == true ]]; then
          [[ -z "$line" ]] && continue
          [[ "$line" =~ ^### ]] && break
          line_clean="$(echo "$line" | sed 's/^- //')"
          SUMMARY="$line_clean"; break
        fi
      done < "$REPORT"
    fi

    if [[ "${#SUMMARY}" -gt 120 ]]; then SUMMARY="${SUMMARY:0:117}..."; fi

    ENTRIES+=("$DATE|$USER|$BASENAME|$SUMMARY")
  done

  IFS=$'\n' read -r -d '' -a SORTED < <(printf '%s\n' "${ENTRIES[@]}" | sort -t'|' -k1,1r; printf '\0') || true

  declare -a RECENT=()
  local OLDER_COUNT=0
  for ENTRY in "${SORTED[@]}"; do
    local D="${ENTRY%%|*}"
    if [[ "$D" > "$CUTOFF_DATE" || "$D" == "$CUTOFF_DATE" ]]; then
      RECENT+=("$ENTRY")
    else
      OLDER_COUNT=$((OLDER_COUNT + 1))
    fi
  done

  {
    echo "# Progress Report Index"
    echo ""
    echo "*Auto-generated: $(date -u +%Y-%m-%d) | ${#ENTRIES[@]} total reports across $(printf '%s\n' "${ENTRIES[@]}" | cut -d'|' -f2 | sort -u | wc -l | tr -d ' ') users*"
    echo ""
    echo "## Recent Reports (last ${RECENT_DAYS} days)"
    echo ""
    if [[ ${#RECENT[@]} -eq 0 ]]; then
      echo "No reports in the last $RECENT_DAYS days."
    else
      echo "| Date | User | Summary |"
      echo "|------|------|---------|"
      for ENTRY in "${RECENT[@]}"; do
        IFS='|' read -r DATE USER BASENAME SUMMARY <<< "$ENTRY"
        local LINK="${USER}/${BASENAME}"
        echo "| $DATE | $USER | [${SUMMARY}](${LINK}) |"
      done
    fi
    echo ""
    if [[ "$OLDER_COUNT" -gt 0 ]]; then
      echo "## Older Reports"
      echo ""
      echo "$OLDER_COUNT reports older than $RECENT_DAYS days. Browse \`logs/progress/<user>/\` directly."
    fi
  } > "$OUTPUT"

  echo "build-indexes: progress index — ${#RECENT[@]} recent, $OLDER_COUNT older"
}

# =============================================================================
# 2. Notes Index
# =============================================================================

build_notes_index() {
  local NOTES_DIR="$KNOWLEDGE_ROOT/notes"
  local OUTPUT="$NOTES_DIR/INDEX.md"
  local TMPFILE
  TMPFILE="$(mktemp)"
  trap 'rm -f "$TMPFILE"' RETURN

  while IFS= read -r -d '' FILE; do
    local BASENAME REL_PATH USER SUBDIR CATEGORY TITLE MOD_DATE
    BASENAME="$(basename "$FILE")"
    [[ "$BASENAME" == "INDEX.md" ]] && continue

    REL_PATH="${FILE#"$NOTES_DIR/"}"
    USER="$(echo "$REL_PATH" | cut -d'/' -f1)"
    [[ "$USER" == "$REL_PATH" ]] && continue

    SUBDIR="$(dirname "$REL_PATH")"
    if [[ "$SUBDIR" == "$USER" ]]; then
      CATEGORY="general"
    else
      CATEGORY="${SUBDIR#"$USER/"}"
    fi

    TITLE="$(grep -m1 '^# ' "$FILE" 2>/dev/null | sed 's/^# //' || true)"
    [[ -z "$TITLE" ]] && TITLE="${BASENAME%.md}"
    if [[ "${#TITLE}" -gt 100 ]]; then TITLE="${TITLE:0:97}..."; fi

    MOD_DATE="$(git -C "$KNOWLEDGE_ROOT" log -1 --format=%cs -- "$FILE" 2>/dev/null || date -r "$FILE" +%Y-%m-%d 2>/dev/null || echo "unknown")"

    printf '%s\t%s\t%s\t%s\t%s\n' "$USER" "$CATEGORY" "$MOD_DATE" "$REL_PATH" "$TITLE" >> "$TMPFILE"
  done < <(find "$NOTES_DIR" -name '*.md' -print0 | sort -z)

  for FILE in "$NOTES_DIR"/*.md; do
    [[ -f "$FILE" ]] || continue
    local BASENAME TITLE MOD_DATE
    BASENAME="$(basename "$FILE")"
    [[ "$BASENAME" == "INDEX.md" ]] && continue
    TITLE="$(grep -m1 '^# ' "$FILE" 2>/dev/null | sed 's/^# //' || true)"
    [[ -z "$TITLE" ]] && TITLE="${BASENAME%.md}"
    MOD_DATE="$(git -C "$KNOWLEDGE_ROOT" log -1 --format=%cs -- "$FILE" 2>/dev/null || echo "unknown")"
    printf '%s\t%s\t%s\t%s\t%s\n' "_shared" "root" "$MOD_DATE" "$BASENAME" "$TITLE" >> "$TMPFILE"
  done

  local TOTAL USERS
  TOTAL="$(wc -l < "$TMPFILE" | tr -d ' ')"
  # `grep -v` exits 1 when it selects nothing, and `pipefail` propagates that
  # through the whole pipeline — which kills the script under `set -e`. That
  # happens exactly when the log repo is empty, i.e. on a brand-new project.
  USERS="$( { cut -f1 "$TMPFILE" | grep -v '^_shared$' || true; } | sort -u | wc -l | tr -d ' ')"

  {
    echo "# Notes Index"
    echo ""
    echo "*Auto-generated: $(date -u +%Y-%m-%d) | $TOTAL notes across $USERS users*"
    echo ""

    local PREV_USER=""
    while IFS=$'\t' read -r USER CATEGORY MOD_DATE REL_PATH TITLE; do
      if [[ "$USER" != "$PREV_USER" ]]; then
        [[ -n "$PREV_USER" ]] && echo ""
        if [[ "$USER" == "_shared" ]]; then
          echo "## Shared"
        else
          echo "## $USER"
        fi
        echo ""
        echo "| Category | Updated | File | Title |"
        echo "|----------|---------|------|-------|"
        PREV_USER="$USER"
      fi
      echo "| $CATEGORY | $MOD_DATE | [$REL_PATH]($REL_PATH) | $TITLE |"
    done < <(sort -t$'\t' -k1,1 -k3,3r "$TMPFILE")
  } > "$OUTPUT"

  echo "build-indexes: notes index — $TOTAL notes across $USERS users"
}

# =============================================================================
# 3. Wiki Index
# =============================================================================
#
# Emits two artifacts:
#   wiki/INDEX.md      — catalog grouped by directory, plus a scope lookup
#   wiki/STALENESS.md  — articles whose sources changed after `updated:`
#
# Articles carry YAML frontmatter (see wiki/schema.md). Two bugs in the
# original root-repo version are fixed here:
#
#   1. It parsed YAML frontmatter but the articles used `**Category**:`
#      bold-markdown, so every field fell back to "unknown".
#   2. Records were joined with tabs and re-read with `IFS=$'\t'`. Tab is an
#      IFS *whitespace* character in bash, so leading tabs were stripped and
#      runs of tabs collapsed — any empty field (root-level article, no tags)
#      shifted every later column left, yielding links like `unknown/unknown.md`.
#      Records now use US (0x1f), which is not IFS whitespace, so empty fields
#      survive intact.

readonly FS=$'\x1f'

build_wiki_index() {
  local WIKI_DIR="$KNOWLEDGE_ROOT/wiki"
  local OUTPUT="$WIKI_DIR/INDEX.md"
  local STALENESS_OUTPUT="$WIKI_DIR/STALENESS.md"

  [[ -d "$WIKI_DIR" ]] || return 0

  local TMPFILE STALE_TMPFILE SCOPE_MAP
  TMPFILE="$(mktemp)"
  STALE_TMPFILE="$(mktemp)"
  SCOPE_MAP="$(mktemp)"
  trap 'rm -f "$TMPFILE" "$STALE_TMPFILE" "$SCOPE_MAP"' RETURN

  local TOTAL=0 STALE_COUNT=0

  while IFS= read -r -d '' FILE; do
    local BASENAME REL_PATH
    BASENAME="$(basename "$FILE")"
    REL_PATH="${FILE#"$WIKI_DIR/"}"

    # Generated or spec files are not articles
    case "$BASENAME" in
      INDEX.md|STALENESS.md|USAGE.md|schema.md|README.md|.gitkeep) continue ;;
    esac

    local TITLE="" CATEGORY="" SCOPE="" TAGS="" UPDATED="" SOURCES=""
    local IN_FRONT=false FRONT_DONE=false IN_SOURCES=false
    while IFS= read -r line; do
      [[ "$FRONT_DONE" == true ]] && break
      if [[ "$line" == "---" ]]; then
        if [[ "$IN_FRONT" == true ]]; then FRONT_DONE=true; continue; fi
        IN_FRONT=true; continue
      fi
      [[ "$IN_FRONT" == true ]] || continue

      # Continuation lines of a block-style `sources:` list
      if [[ "$IN_SOURCES" == true ]]; then
        if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
          SOURCES+="$(echo "$line" | sed 's/^[[:space:]]*- *//')"$'\n'
          continue
        fi
        IN_SOURCES=false
      fi

      case "$line" in
        title:*)    TITLE="$(echo "$line" | sed 's/^title: *//; s/^"//; s/"$//')" ;;
        category:*) CATEGORY="$(echo "$line" | sed 's/^category: *//')" ;;
        scope:*)    SCOPE="$(echo "$line" | sed 's/^scope: *//; s/\[//; s/\]//')" ;;
        tags:*)     TAGS="$(echo "$line" | sed 's/^tags: *//; s/\[//; s/\]//')" ;;
        updated:*)  UPDATED="$(echo "$line" | sed 's/^updated: *//')" ;;
        sources:*)
          local INLINE="${line#sources:}"
          INLINE="$(echo "$INLINE" | sed 's/^ *//; s/\[//; s/\]//')"
          if [[ -n "$INLINE" ]]; then
            SOURCES+="$(echo "$INLINE" | tr ',' '\n' | sed 's/^ *//; s/ *$//')"$'\n'
          else
            IN_SOURCES=true
          fi
          ;;
      esac
    done < "$FILE"

    [[ -z "$TITLE" ]]    && TITLE="${BASENAME%.md}"
    [[ -z "$CATEGORY" ]] && CATEGORY="uncategorized"
    [[ -z "$UPDATED" ]]  && UPDATED="unknown"

    local DIR
    DIR="$(dirname "$REL_PATH")"
    [[ "$DIR" == "." ]] && DIR=""

    # An article is STALE when a frontmatter source has a git commit newer
    # than the article's `updated:` date. URLs and untracked paths are skipped.
    local STATUS="FRESH" STALE_DETAIL=""
    if [[ "$UPDATED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ && -n "$SOURCES" ]]; then
      while IFS= read -r SRC; do
        [[ -z "$SRC" || "$SRC" == http://* || "$SRC" == https://* ]] && continue
        local RESOLVED SRC_DATE
        RESOLVED="$(realpath -m "$PROJECT_ROOT/$SRC" 2>/dev/null || true)"
        [[ -n "$RESOLVED" && -f "$RESOLVED" ]] || continue
        SRC_DATE="$(git -C "$(dirname "$RESOLVED")" log -1 --format=%cs -- "$RESOLVED" 2>/dev/null || true)"
        if [[ -n "$SRC_DATE" && "$SRC_DATE" > "$UPDATED" ]]; then
          STATUS="STALE"
          STALE_DETAIL+="  - \`$SRC\` changed $SRC_DATE"$'\n'
        fi
      done <<< "$SOURCES"
    fi

    TOTAL=$((TOTAL + 1))
    if [[ "$STATUS" == "STALE" ]]; then
      STALE_COUNT=$((STALE_COUNT + 1))
      local STALE_BLOCK
      STALE_BLOCK="$(printf '%s\n' "## [${TITLE}](${REL_PATH})" "" \
        "Article \`updated:\` ${UPDATED} — sources modified since:" "" "$STALE_DETAIL")"
      printf '%s\t%s\t%s\n' "$UPDATED" "$REL_PATH" \
        "$(printf '%s' "$STALE_BLOCK" | base64 -w0)" >> "$STALE_TMPFILE"
    fi

    # scope lookup: one row per (repo, article)
    if [[ -n "$SCOPE" ]]; then
      local S
      while IFS= read -r S; do
        S="$(echo "$S" | sed 's/^ *//; s/ *$//; s/^"//; s/"$//')"
        [[ -n "$S" ]] && printf '%s|%s|%s\n' "$S" "$TITLE" "$REL_PATH" >> "$SCOPE_MAP"
      done < <(echo "$SCOPE" | tr ',' '\n')
    fi

    printf '%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
      "$DIR" "$FS" "$CATEGORY" "$FS" "$TITLE" "$FS" "$REL_PATH" "$FS" \
      "$TAGS" "$FS" "$UPDATED" "$FS" "$STATUS" >> "$TMPFILE"
  done < <(find "$WIKI_DIR" -name '*.md' -print0 | sort -z)

  # Emit both artifacts even with no articles. A new project's README points at
  # them, and a missing file reads as a broken build rather than an empty wiki.
  if [[ "$TOTAL" -eq 0 ]]; then
    {
      echo "# Wiki Index"
      echo ""
      echo "*Auto-generated by \`scripts/build-indexes.sh\` — do not edit by hand.*"
      echo ""
      echo "No articles yet. Create one with \`/project-wiki create <topic>\`, or"
      echo "compile from session logs with \`/project-wiki compile\`. See"
      echo "[schema.md](schema.md) for the article format."
    } > "$OUTPUT"
    {
      echo "# Wiki Staleness Report"
      echo ""
      echo "*Auto-generated by \`scripts/build-indexes.sh\` — do not edit by hand.*"
      echo ""
      echo "No articles yet, so nothing can be stale."
    } > "$STALENESS_OUTPUT"
    echo "build-indexes: wiki index — 0 articles"
    return 0
  fi

  {
    echo "# Wiki Index"
    echo ""
    echo "*Auto-generated by \`scripts/build-indexes.sh\` — do not edit by hand.*"
    echo ""
    echo "$TOTAL articles | $STALE_COUNT stale | updated $(date -u +%Y-%m-%d)"
    echo ""

    local PREV_DIR="__none__"
    while IFS="$FS" read -r DIR CATEGORY TITLE REL_PATH TAGS UPDATED STATUS; do
      local DISPLAY_DIR="${DIR:-root}"
      if [[ "$DISPLAY_DIR" != "$PREV_DIR" ]]; then
        [[ "$PREV_DIR" != "__none__" ]] && echo ""
        echo "### ${DISPLAY_DIR}/"
        echo ""
        echo "| Article | Category | Tags | Updated | Status |"
        echo "|---------|----------|------|---------|--------|"
        PREV_DIR="$DISPLAY_DIR"
      fi
      local MARK="$STATUS"
      [[ "$STATUS" == "STALE" ]] && MARK="**STALE**"
      echo "| [${TITLE}](${REL_PATH}) | ${CATEGORY} | ${TAGS} | ${UPDATED} | ${MARK} |"
    done < <(sort -t"$FS" -k1,1 -k3,3 "$TMPFILE")

    if [[ -s "$SCOPE_MAP" ]]; then
      echo ""
      echo "## Scope Lookup"
      echo ""
      echo "Which articles cover which repo."
      echo ""
      sort -t'|' -k1,1 -k2,2 "$SCOPE_MAP" | awk -F'|' '
        $1 != prev { if (prev != "") print ""; print "**" $1 "**"; print ""; prev = $1 }
        { print "- [" $2 "](" $3 ")" }
      '
    fi
  } > "$OUTPUT"

  {
    echo "# Wiki Staleness Report"
    echo ""
    echo "*Auto-generated by \`scripts/build-indexes.sh\` — do not edit by hand.*"
    echo ""
    echo "An article is STALE when a frontmatter source has a git commit newer"
    echo "than the article's \`updated:\` date. External URLs and untracked paths"
    echo "are not checked. Consumed by \`/wiki:refresh\`."
    echo ""
    if [[ "$STALE_COUNT" -eq 0 ]]; then
      echo "All $TOTAL articles are fresh as of $(date -u +%Y-%m-%d)."
    else
      echo "$STALE_COUNT of $TOTAL articles are stale as of $(date -u +%Y-%m-%d), stalest first."
      echo ""
      while IFS=$'\t' read -r _UPDATED _REL B64; do
        printf '%s\n\n' "$(printf '%s' "$B64" | base64 -d)"
      done < <(sort -t$'\t' -k1,1 -k2,2 "$STALE_TMPFILE")
    fi
  } > "$STALENESS_OUTPUT"

  echo "build-indexes: wiki index — $TOTAL articles ($STALE_COUNT stale)"
}

# =============================================================================
# Run all
# =============================================================================

build_progress_index
build_notes_index
build_wiki_index
