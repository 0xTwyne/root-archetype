#!/usr/bin/env bash
set -euo pipefail

# Hook: PreToolUse (matcher: "Edit|Write")
# Merged guard: secret scan → log isolation → config tamper-proofing

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
PATTERNS_FILE="$PROJECT_DIR/scripts/hooks/lib/secret-patterns.txt"
MAINTAINERS_FILE="$PROJECT_DIR/MAINTAINERS.json"

source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
hook_resolve_log_repo 2>/dev/null || true
trap 'hook_fail_open "pre-edit-guard" "unexpected error"' ERR

INPUT="$(cat)"
if ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    echo "pre-edit-guard: could not parse hook input as JSON — allowing" >&2
    exit 0
fi
# Prefer .tool_input; fall back to the whole object for the legacy flat shape.
TOOL_INPUT="$(echo "$INPUT" | jq -c '.tool_input // .')"
FILE_PATH="$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || echo "")"
CONTENT="$(echo "$TOOL_INPUT" | jq -r '.content // .new_string // empty' 2>/dev/null || echo "")"

if [[ -z "$FILE_PATH" ]]; then
  hook_silent
fi

CONTEXT=""
add_context() {
  if [[ -n "$CONTEXT" ]]; then CONTEXT+=$'\n\n'; fi
  CONTEXT+="$1"
}

# --- Secret scan ---
if [[ -n "$CONTENT" && -f "$PATTERNS_FILE" ]]; then
  while IFS=$'\t' read -r label regex replacement; do
    [[ -z "$label" || -z "$regex" ]] && continue
    [[ "$label" == \#* ]] && continue
    if echo "$CONTENT" | grep -qE "$regex"; then
      hook_block "Secret detected in file content. Pattern: $label. Target: $FILE_PATH. NEVER write secrets to tracked files."
    fi
  done < "$PATTERNS_FILE"
fi

# --- Log isolation (applies to paths in both root repo and log repo) ---
REL_PATH=""
IS_LOG_PATH=false

# Check if path is in the log repo. IN_ROOT_REPO records which one matched:
# the log repo usually lives INSIDE the root repo (repos/<name>/), so a bare
# "$FILE_PATH == $PROJECT_DIR/*" test later cannot distinguish the two.
_LOG_DIR="${LOG_REPO_DIR:-$PROJECT_DIR}"
IN_ROOT_REPO=false
if [[ "$_LOG_DIR" != "$PROJECT_DIR" && "$FILE_PATH" == "$_LOG_DIR"/* ]]; then
  REL_PATH="${FILE_PATH#$_LOG_DIR/}"
elif [[ "$FILE_PATH" == "$PROJECT_DIR"/* ]]; then
  REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
  IN_ROOT_REPO=true
fi

if [[ -n "$REL_PATH" ]]; then
  case "$REL_PATH" in
    logs/audit/*|logs/progress/*|notes/*)
      IS_LOG_PATH=true
      ;;
  esac
fi

# Root knowledge/ no longer exists in split-mode projects — taxonomy, research
# and the compiled wiki all live in the knowledge repo. A write there is a
# stale-path mistake, not a choice. (Single-repo mode, e.g. the archetype
# itself, keeps root knowledge/ as its own KB and is untouched: _LOG_DIR ==
# PROJECT_DIR there, so this never fires.)
if [[ "$IN_ROOT_REPO" == "true" && "$_LOG_DIR" != "$PROJECT_DIR" ]]; then
  case "$REL_PATH" in
    knowledge/*)
      hook_block "BLOCKED: root knowledge/ is retired in split mode. Taxonomy: ${_LOG_DIR}/wiki/taxonomy.yaml; research: ${_LOG_DIR}/wiki/research/; wiki: ${_LOG_DIR}/wiki/."
      ;;
  esac
fi

if [[ "$IS_LOG_PATH" == "true" ]]; then
  # In split mode, BLOCK writes to the root repo's skeletal stubs — before any
  # exemption, so the shared files (INDEX.md, notes/handoffs/*) are covered too:
  # in the root repo those are exactly the log-repo artifacts that must not fork.
  # This used to be a warning, and a warned write still happened; the root repo
  # accumulated log data that existed in the log repo nowhere. In single-repo
  # mode (_LOG_DIR == PROJECT_DIR) root logs/ IS the log location and this
  # branch never fires.
  if [[ "$_LOG_DIR" != "$PROJECT_DIR" && "$IN_ROOT_REPO" == "true" ]]; then
    hook_block "BLOCKED: $REL_PATH is a root-repo stub. Logs, notes and handoffs live in the log repo — write to ${_LOG_DIR}/$REL_PATH instead."
  fi

  # Exempt shared files from the per-user ownership check (log repo only)
  case "$REL_PATH" in
    logs/progress/INDEX.md|notes/handoffs/*|notes/INDEX.md|notes/agent-changelog.md)
      IS_LOG_PATH=false
      ;;
  esac
  [[ "$(basename "$REL_PATH")" == ".gitkeep" ]] && IS_LOG_PATH=false
fi

if [[ "$IS_LOG_PATH" == "true" ]]; then
  hook_load_identity
  if [[ "$SESSION_USER" != "unknown" ]]; then
    TARGET_USER=""
    case "$REL_PATH" in
      logs/audit/*) TARGET_USER="$(echo "$REL_PATH" | cut -d/ -f3)" ;;
      logs/progress/*) TARGET_USER="$(echo "$REL_PATH" | cut -d/ -f3)" ;;
      notes/*) TARGET_USER="$(echo "$REL_PATH" | cut -d/ -f2)" ;;
    esac

    if [[ -n "$TARGET_USER" && "$TARGET_USER" != "$SESSION_USER" ]]; then
      hook_block "BLOCKED: Cross-user write denied. Path targets \"$TARGET_USER\" but session belongs to \"$SESSION_USER\". File: $REL_PATH"
    fi
  fi
fi

# --- Config tamper-proofing ---
if [[ ! -f "$MAINTAINERS_FILE" ]]; then
  if [[ -n "$CONTEXT" ]]; then hook_warn "$CONTEXT"; fi
  hook_silent
fi

REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
USER_EMAIL="$(git config user.email 2>/dev/null || echo "")"

# --- Which repo governs this path? ---
# A path under repos/<name>/ is governed by that child repo: its own maintainers
# from MAINTAINERS.json -> repo_maintainers[<name>], plus the global maintainers.
# Anything else is governed by the root project and its global maintainers alone.
GOVERNING_REPO=""
CORE_REL="$REL_PATH"
case "$REL_PATH" in
  repos/*/*)
    GOVERNING_REPO="${REL_PATH#repos/}"
    GOVERNING_REPO="${GOVERNING_REPO%%/*}"
    CORE_REL="${REL_PATH#repos/${GOVERNING_REPO}/}"
    ;;
esac

IS_CORE=false
# .claude/* and CLAUDE.md are tracked in git and protected at runtime.
# CORE_REL is repo-relative, so a child repo's own config is protected
# the same way the root's is — governed by that child's maintainers.
case "$CORE_REL" in
  .claude/*|CLAUDE.md|AGENT.md|scripts/*|docs/*)
    IS_CORE=true
    ;;
esac

if [[ "$IS_CORE" == "true" ]]; then
  # The maintainer set: global_maintainers, plus repo_maintainers[<repo>] when
  # the path belongs to a registered child repo.
  #
  # This read used to be `(.global // [])`. No MAINTAINERS.json has ever had a
  # `global` key — the schema this template ships, and the one init-wizard
  # writes, is `global_maintainers` — so the lookup always returned [], every
  # user resolved as a non-maintainer, and $MAINTAINER_LIST rendered empty in
  # both messages. `repo_maintainers` was written by register-repo.sh and read
  # by nothing at all.
  # Resolve BOTH sides through the alias registry before comparing.
  #
  # The naive comparison — this machine's `git config user.email` against the
  # raw strings in MAINTAINERS.json — fails in both directions, and both were
  # reproduced before this was written:
  #
  #   Grants wrongly. git user.email is inherited from the container image, so
  #   every collaborator in a shared devcontainer presents the same address. A
  #   session belonging to someone else passed the maintainer check purely by
  #   inheriting it.
  #
  #   Blocks wrongly. A maintainer whose commits carry a GitHub noreply address
  #   is not the string in MAINTAINERS.json, so wiring this guard hard-blocked
  #   the project maintainer out of scripts/hooks/ on his own machine.
  #
  # So: a maintainer entry that the registry has CLAIMED is matched against the
  # session's canonical user, which comes from the one resolver in
  # session-start.sh. An entry nobody has claimed keeps the old e-mail
  # comparison, which is the correct day-one behaviour before anyone registers.
  #
  # This is not authentication. Anyone who can run `git config` or `gh auth`
  # can present as someone else, and the guard fails open on timeout by harness
  # design. It stops accidents and records intent. Repository permissions on
  # the forge are the actual control.
  hook_load_identity
  ACTOR="$SESSION_USER"
  if declare -F hook_canonical_user >/dev/null 2>&1; then
    _AC="$(hook_canonical_user "$ACTOR" 2>/dev/null || echo "")"
    [[ -n "$_AC" ]] && ACTOR="$_AC"
  fi

  IS_MAINTAINER="false"
  while IFS= read -r _m; do
    [[ -n "$_m" ]] || continue
    _owner=""
    if declare -F hook_identity_owner >/dev/null 2>&1; then
      _owner="$(hook_identity_owner "$_m" 2>/dev/null || echo "")"
    fi
    if [[ -n "$_owner" ]]; then
      # Claimed: only that person qualifies, whichever e-mail they commit with.
      if [[ "${ACTOR,,}" == "${_owner,,}" && "$ACTOR" != "unknown" ]]; then
        IS_MAINTAINER="true"; break
      fi
    else
      # Unclaimed: fall back to the e-mail comparison.
      if [[ -n "$USER_EMAIL" && "${USER_EMAIL,,}" == "${_m,,}" ]]; then
        IS_MAINTAINER="true"; break
      fi
    fi
  done < <(jq -r --arg repo "$GOVERNING_REPO" '
    ((.global_maintainers // [])
     + (if $repo == "" then [] else (.repo_maintainers[$repo] // []) end))
    | unique | .[]' "$MAINTAINERS_FILE" 2>/dev/null || true)


  if [[ "$IS_MAINTAINER" == "true" ]]; then
    if [[ -n "$CONTEXT" ]]; then hook_warn "$CONTEXT"; fi
    hook_silent
  fi

  # Hard-block behavioral config files for non-maintainers
  IS_HARD_BLOCK=false
  case "$CORE_REL" in
    CLAUDE.md|.claude/settings.json|.claude/settings.local.json|scripts/hooks/*|.claude/agents/*)
      IS_HARD_BLOCK=true
      ;;
  esac

  MAINTAINER_LIST="$(jq -r --arg repo "$GOVERNING_REPO" '
    ((.global_maintainers // [])
     + (if $repo == "" then [] else (.repo_maintainers[$repo] // []) end))
    | unique | join(", ")' "$MAINTAINERS_FILE" 2>/dev/null || echo "")"
  [[ -n "$MAINTAINER_LIST" ]] || MAINTAINER_LIST="unknown"

  _WHOSE="the project"
  [[ -n "$GOVERNING_REPO" ]] && _WHOSE="child repo '$GOVERNING_REPO'"

  if [[ "$IS_HARD_BLOCK" == "true" ]]; then
    hook_block "BLOCKED: $REL_PATH is a protected config file of $_WHOSE, maintained by $MAINTAINER_LIST. Submit changes via PR."
  fi

  add_context "WARNING: You are editing a core file of $_WHOSE, maintained by $MAINTAINER_LIST. Changes on session branch will be included in auto-PR at session end."
fi

if [[ -n "$CONTEXT" ]]; then
  hook_warn "$CONTEXT"
fi

hook_silent
