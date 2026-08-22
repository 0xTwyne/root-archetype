#!/bin/bash
set -euo pipefail

# Generate notes/handoffs/INDEX.md by scanning all notes/*/handoffs/**/*.md
#
# Usage:
#   generate-handoff-index.sh [ROOT_DIR]
#
# ROOT_DIR defaults to git toplevel. Pass a worktree path when called
# from push-logs.sh.

# ROOT_DIR defaults to the LOG REPO, not the root repo. Handoffs and their index
# live there. Defaulting to git toplevel meant a bare invocation scanned the root
# repo, found no per-user handoff directories, and wrote an empty INDEX.md into
# the root repo's notes/ — which is a documentation stub. push-logs.sh always
# passes an explicit path, so only a direct call hit it.

# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

_repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_default_dir="$_repo_root"
if [[ -f "$_repo_root/.archetype-manifest.json" ]] && command -v jq >/dev/null 2>&1; then
  _log_name="$(jq -r '.log_repo_name // empty' "$_repo_root/.archetype-manifest.json" 2>/dev/null || echo "")"
  if [[ -n "$_log_name" && -d "$_repo_root/repos/$_log_name" ]]; then
    _default_dir="$_repo_root/repos/$_log_name"
  fi
fi
ROOT_DIR="${1:-$_default_dir}"
NOTES_DIR="$ROOT_DIR/notes"
INDEX_FILE="$NOTES_DIR/handoffs/INDEX.md"

if [[ ! -d "$NOTES_DIR" ]]; then
  echo "generate-handoff-index: no notes/ directory found in $ROOT_DIR" >&2
  exit 0
fi

mkdir -p "$(dirname "$INDEX_FILE")"

# --- Collect handoff metadata ---
# Format per line: user|status|created|title|relpath
ENTRIES=()

while IFS= read -r -d '' file; do
  # Skip non-handoff files
  basename="$(basename "$file")"
  case "$basename" in
    INDEX.md|README.md|.gitkeep) continue ;;
  esac

  # Extract user from path: notes/<user>/handoffs/...
  relpath="${file#"$NOTES_DIR/"}"
  user="${relpath%%/*}"

  # Determine status from directory structure
  # Files in completed/ → completed; files directly in handoffs/ → active
  case "$relpath" in
    */completed/*) status="completed" ;;
    */active/*)    status="active" ;;
    *)
      # Fallback: parse **Status**: line from file content
      status_line="$(grep -m1 -oP '^\*\*Status\*\*:\s*\K.+' "$file" 2>/dev/null || true)"
      if [[ -n "$status_line" ]]; then
        status_lower="$(echo "$status_line" | tr '[:upper:]' '[:lower:]' | xargs)"
        case "$status_lower" in
          completed|complete|done) status="completed" ;;
          blocked)                 status="blocked" ;;
          *)                       status="active" ;;
        esac
      else
        status="active"
      fi
      ;;
  esac

  # Extract title: first H1 heading
  title="$(grep -m1 -oP '^#\s+\K.+' "$file" 2>/dev/null || echo "$basename")"

  # Extract created date: **Created**: YYYY-MM-DD
  created="$(grep -m1 -oP '^\*\*Created\*\*:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}' "$file" 2>/dev/null || true)"

  # Then a YYYY-MM-DD_ filename prefix, the convention for new handoffs.
  if [[ -z "$created" ]] && [[ "$basename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_ ]]; then
    created="${BASH_REMATCH[1]}"
  fi

  # Then the commit that added the file — the closest thing to a real creation
  # date, and stable across clones. This must come before the mtime fallback:
  # mtime is set by checkout, so on any fresh clone every handoff appeared to
  # have been written today, and regenerating the index silently overwrote real
  # historical dates with the clone date.
  if [[ -z "$created" ]]; then
    # `tail -1` takes the EARLIEST add, not the latest. A file that was moved
    # (e.g. handoffs/active -> handoffs/completed) has several add-commits, and
    # `-1` would report the move date as the creation date.
    created="$(git -C "$ROOT_DIR" log --diff-filter=A --format=%ad --date=short -- "$file" 2>/dev/null | tail -1 || true)"
  fi

  # Last resort: mtime (untracked file, or not a git repo).
  if [[ -z "$created" ]]; then
    created="$(date -r "$file" +%Y-%m-%d 2>/dev/null || stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")"
  fi

  # Relative link from notes/handoffs/INDEX.md to the file
  linkpath="../$relpath"

  ENTRIES+=("${user}|${status}|${created}|${title}|${linkpath}")
done < <(find "$NOTES_DIR" -path "*/handoffs/*.md" -print0 2>/dev/null | sort -z)

# --- Group entries by user, then status ---

# Get sorted unique users
USERS=()
for entry in "${ENTRIES[@]}"; do
  USERS+=("${entry%%|*}")
done
# Deduplicate and sort. Guard the empty case: `printf '%s\n' "${ARR[@]}"` on an
# empty array still prints one blank line, so USERS would become a single
# empty-string "user" and the index would grow a headerless `## ` section.
if [[ ${#USERS[@]} -gt 0 ]]; then
  mapfile -t USERS < <(printf '%s\n' "${USERS[@]}" | sort -u)
fi

# --- Write INDEX.md ---
{
  echo "# Handoff Index"
  echo ""
  echo "> Auto-generated by scanning all notes/*/handoffs/*.md. Do not edit manually."
  echo "> Last updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

  for user in "${USERS[@]}"; do
    echo ""
    echo "## $user"

    # Collect entries for this user, grouped by status
    for status_group in active blocked completed; do
      group_lines=()
      for entry in "${ENTRIES[@]}"; do
        IFS='|' read -r e_user e_status e_created e_title e_link <<< "$entry"
        if [[ "$e_user" == "$user" && "$e_status" == "$status_group" ]]; then
          group_lines+=("- [${e_title}](${e_link}) — ${e_created}")
        fi
      done

      if [[ ${#group_lines[@]} -gt 0 ]]; then
        # Capitalize status group header
        header="$(echo "${status_group:0:1}" | tr '[:lower:]' '[:upper:]')${status_group:1}"
        echo ""
        echo "### $header"
        echo ""
        for line in "${group_lines[@]}"; do
          echo "$line"
        done
      fi
    done
  done
} > "${INDEX_FILE}.tmp"

# Only replace the real file when something other than the timestamp changed.
# Rewriting it unconditionally left the file permanently dirty in git, so
# push-logs committed and pushed a no-op change on every single run and its
# "nothing to push" branch could never be reached.
if [[ -f "$INDEX_FILE" ]] && \
   diff -q <(grep -v '^> Last updated:' "$INDEX_FILE") \
           <(grep -v '^> Last updated:' "${INDEX_FILE}.tmp") >/dev/null 2>&1; then
    rm -f "${INDEX_FILE}.tmp"
    echo "generate-handoff-index: $INDEX_FILE unchanged (${#ENTRIES[@]} entries, ${#USERS[@]} users)"
else
    mv "${INDEX_FILE}.tmp" "$INDEX_FILE"
    echo "generate-handoff-index: wrote $INDEX_FILE (${#ENTRIES[@]} entries, ${#USERS[@]} users)"
fi
