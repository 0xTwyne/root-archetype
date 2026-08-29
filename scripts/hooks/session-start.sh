#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: SessionStart
# 1. Resolves username and persists to .session-identity
# 2. Pulls latest main, creates session branch
# 3. Creates per-user log/notes directories (in log repo)
# 4. Loads agent registry + facts cache
# 5. Initializes session stats tracker

# --- Dry-run / argv mode ---
# Print the resolved launch chain (paths, env, tools, branch plan) without
# performing any side effects. Useful for security review and debugging.
#   bash session-start.sh --argv      # human-readable
#   bash session-start.sh --argv json # JSON
if [[ "${1:-}" == "--argv" || "${1:-}" == "--dry-run" ]]; then
  hook_resolve_log_repo 2>/dev/null || true
  user="$(git -C "$PROJECT_DIR" config user.name 2>/dev/null || echo "${USER:-unknown}")"
  user="$(printf '%s' "$user" | tr -cd 'a-zA-Z0-9_-')"
  [[ -z "$user" ]] && user="unknown"
  short_id="$(date -u +%Y%m%d_%H%M%S)_$$"
  branch_plan="session/${short_id:0:12}_$(date -u +%Y-%m-%d)"
  if [[ "${2:-}" == "json" ]]; then
    audit_lines=""
    if declare -F hook_tools_audit >/dev/null 2>&1; then
      audit_lines="$(hook_tools_audit 2>/dev/null | jq -R -s 'split("\n") | map(select(length>0) | split("\t") | {name:.[0], path:.[1], status:.[2]})')"
    else
      audit_lines='[]'
    fi
    jq -cn \
      --arg script "$SCRIPT_DIR/session-start.sh" \
      --arg project "$PROJECT_DIR" \
      --arg log_repo "${LOG_REPO_DIR:-$PROJECT_DIR}" \
      --arg user "$user" \
      --arg branch "$branch_plan" \
      --arg identity "$PROJECT_DIR/.session-identity" \
      --arg stats "$PROJECT_DIR/.session-stats" \
      --argjson tools "$audit_lines" \
      '{script:$script, project:$project, log_repo:$log_repo, user_planned:$user, branch_planned:$branch, writes:[$identity,$stats], tools:$tools, side_effects:["create branch","fetch/pull origin/main","create log dirs","write .session-identity","write .session-stats"]}'
  else
    echo "session-start.sh --argv (dry-run, no side effects)"
    echo "  script    : $SCRIPT_DIR/session-start.sh"
    echo "  project   : $PROJECT_DIR"
    echo "  log_repo  : ${LOG_REPO_DIR:-$PROJECT_DIR}"
    echo "  user_plan : $user"
    echo "  branch    : $branch_plan"
    echo "  writes    : $PROJECT_DIR/.session-identity, $PROJECT_DIR/.session-stats"
    echo "  side fx   : create session branch; fetch/pull origin/main; mkdir per-user log dirs"
    echo "  tools     :"
    if declare -F hook_tools_audit >/dev/null 2>&1; then
      hook_tools_audit | sed 's/^/              /'
    else
      echo "              (hook_tools_audit unavailable)"
    fi
  fi
  exit 0
fi

# Resolve log repo early (needed for dir creation and facts loading)
hook_resolve_log_repo 2>/dev/null || true

INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="ses_$(date -u +%Y%m%d_%H%M%S)_$$"
fi

SHORT_SESSION="$(echo "$SESSION_ID" | head -c 12)"
DATE_TAG="$(date -u +%Y-%m-%d)"
BRANCH_NAME="session/${SHORT_SESSION}_${DATE_TAG}"

# --- Resolve username ---
SESSION_USER=""

# 1. Try GitHub CLI
if [[ -z "$SESSION_USER" ]] && command -v gh &>/dev/null; then
  SESSION_USER="$(gh api user --jq '.login' 2>/dev/null || echo "")"
fi

# 2. Try git config
if [[ -z "$SESSION_USER" ]]; then
  SESSION_USER="$(git config user.name 2>/dev/null || echo "")"
fi

# 3. Try $USER env var
if [[ -z "$SESSION_USER" ]]; then
  SESSION_USER="${USER:-}"
fi

# 4. Absolute fallback
if [[ -z "$SESSION_USER" ]]; then
  SESSION_USER="unknown"
fi

# Sanitize to [a-zA-Z0-9_-]
SESSION_USER="$(echo "$SESSION_USER" | tr -cd 'a-zA-Z0-9_-')"

# Canonicalise through the log repo's alias registry, so one person maps to ONE
# directory regardless of which fallback above produced the name. Without this,
# the same human is "dmrobotix" where gh is authenticated and "MargotPaez" where
# only git config is — and their history silently splits in two.
if declare -F hook_canonical_user >/dev/null 2>&1; then
  _CANON="$(hook_canonical_user "$SESSION_USER" 2>/dev/null || echo "")"
  [[ -n "$_CANON" ]] && SESSION_USER="$_CANON"
fi
[[ -z "$SESSION_USER" ]] && SESSION_USER="unknown"

# Resolve project name from manifest or directory basename
ROOT_REPO_NAME="$(jq -r '.template_values.PROJECT_NAME // empty' "$PROJECT_DIR/.archetype-manifest.json" 2>/dev/null || echo "")"
[[ -z "$ROOT_REPO_NAME" ]] && ROOT_REPO_NAME="$(basename "$PROJECT_DIR")"

# Capture the OUTGOING session before overwriting the identity file.
# A session killed outright (SIGKILL, closed terminal, host shutdown) never runs
# its SessionEnd hook, so no amount of hardening inside that hook can produce a
# close record. The next session start is the only place that still knows the
# dead session's id — after the write below, it is gone.
PREV_SESSION_ID=""
if [[ -f "$PROJECT_DIR/.session-identity" ]]; then
  PREV_SESSION_ID="$(jq -r '.session_id // empty' "$PROJECT_DIR/.session-identity" 2>/dev/null | tr -d '\r' || echo "")"
fi

# Write .session-identity (gitignored) — read by all hooks
jq -cn \
  --arg session_id "$SESSION_ID" \
  --arg user "$SESSION_USER" \
  --arg branch "$BRANCH_NAME" \
  --arg root_repo "$ROOT_REPO_NAME" \
  --arg root_repo_path "$PROJECT_DIR" \
  --arg log_repo_path "${LOG_REPO_DIR:-$PROJECT_DIR}" \
  '{session_id: $session_id, user: $user, branch: $branch, root_repo: $root_repo, root_repo_path: $root_repo_path, log_repo_path: $log_repo_path}' \
  > "$PROJECT_DIR/.session-identity"

# --- Create per-user directories (in log repo) ---
# `|| true` because an absent log repo must not abort the session — the point of
# the run is to reach the "CHILD REPO(S) NOT CLONED" warning below and say so.
# It creates nothing when unresolved, by design.
hook_ensure_log_dirs "$SESSION_USER" || true

# Initialize session stats tracker (gitignored)
echo '{"tool_calls":0,"subagents":0,"file_modifications":0}' > "$PROJECT_DIR/.session-stats"

# --- Pull latest main before branching ---
CURRENT_BRANCH="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
PULL_STATUS=""
# Whether origin was actually reached. Without this, an offline session cannot
# tell "up to date" from "never asked": rev-list against a week-old origin/main
# returns 0 and reads as an all-clear.
REMOTE_OK=0
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  if GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" pull --ff-only origin main 2>/dev/null; then
    PULL_STATUS="main updated"
    REMOTE_OK=1
  else
    PULL_STATUS="pull failed (may have local changes)"
    # --ff-only refuses on any local commit or divergence, and may refuse before
    # updating the remote ref. Fetch anyway so the behind-count below compares
    # against something current — otherwise the one case that most needs the
    # warning is the case that cannot produce it.
    if GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" fetch origin main 2>/dev/null; then
      REMOTE_OK=1
    fi
  fi
else
  if GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" fetch origin main 2>/dev/null; then
    PULL_STATUS="fetched origin/main"
    REMOTE_OK=1
  else
    PULL_STATUS="could not reach origin"
  fi
fi

# --- Is this clone behind main? ---
#
# .claude/ is tracked, so `git pull` is the ONLY delivery mechanism for skills,
# commands, hooks and settings.json. A collaborator whose clone is behind is not
# merely reading stale docs — they are running without hooks that exist on main,
# and nothing used to say so. PULL_STATUS was computed here and never read: the
# string "pull failed (may have local changes)" was assigned and discarded, so
# the failure that strands someone was the one thing guaranteed to be silent.
#
# Three cases this must cover, all previously invisible:
#   1. on main, --ff-only refused (local commits or divergence)
#   2. on a session branch, where nothing pulls at all — only a fetch
#   3. a new session branch cut from an already-stale branch, which compounds
#      session over session because checkout -b branches from CURRENT_BRANCH
STALE_WARNING=""
if [[ "$REMOTE_OK" -eq 1 ]]; then
  # `|| echo 0` matters under `set -e`: rev-list exits non-zero when origin/main
  # is missing (a clone that has never fetched), which would abort the session.
  BEHIND="$(git -C "$PROJECT_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [[ "$BEHIND" =~ ^[0-9]+$ ]] && [[ "$BEHIND" -gt 0 ]]; then
    # Name the paths that change how a session behaves. "3 commits behind" is
    # ignorable; "3 commits behind, including .claude/settings.json" is not.
    AGENT_FILES="$(git -C "$PROJECT_DIR" diff --name-only "HEAD...origin/main" -- \
        .claude/ scripts/hooks/ agents/ CLAUDE.md AGENT.md 2>/dev/null | head -6 || true)"
    STALE_WARNING="\nLOCAL CLONE IS ${BEHIND} COMMIT(S) BEHIND origin/main.\n"
    if [[ -n "$AGENT_FILES" ]]; then
      STALE_WARNING+="Includes agent files — this session is running WITHOUT them:\n"
      while IFS= read -r _f; do
        [[ -n "$_f" ]] && STALE_WARNING+="  $_f\n"
      done <<< "$AGENT_FILES"
    fi
    if [[ "$CURRENT_BRANCH" == "main" ]]; then
      STALE_WARNING+="Fix: git pull --ff-only origin main   (it refused — check for local commits)\n"
    else
      STALE_WARNING+="You were on '${CURRENT_BRANCH}', so this session branched from a stale base.\n"
      STALE_WARNING+="Fix: git checkout main && git pull --ff-only, then start a new session.\n"
    fi
  fi
elif [[ "$CURRENT_BRANCH" != "unknown" ]]; then
  STALE_WARNING="\nCould not reach origin — clone freshness is UNKNOWN, not confirmed.\n"
fi

# Create session branch.
# A silent failure here is costly: session-end only commits when the current
# branch matches session/*, so staying on main means the whole session's work
# is never committed — and nothing would have said so.
# BRANCH_WARNING is appended to CONTEXT further down: CONTEXT is assigned (not
# appended to) after this point, so writing to it here would be discarded.
BRANCH_WARNING=""
if [[ "$CURRENT_BRANCH" != "$BRANCH_NAME" ]]; then
  if ! branch_err="$(git -C "$PROJECT_DIR" checkout -b "$BRANCH_NAME" 2>&1 >/dev/null)"; then
    BRANCH_WARNING="\nWARNING: could not create session branch $BRANCH_NAME — still on $CURRENT_BRANCH.\n"
    BRANCH_WARNING+="Session-end only auto-commits on a session/* branch, so work here will NOT be committed automatically.\n"
    [[ -n "$branch_err" ]] && BRANCH_WARNING+="  ${branch_err}\n"
  fi
fi

# Log session start
if [[ -f "$PROJECT_DIR/scripts/utils/agent_log.sh" ]]; then
  source "$PROJECT_DIR/scripts/utils/agent_log.sh"

  # Close out a predecessor that never got to write its own SESSION_END.
  # Only when it genuinely has a START and no END — never invent a close for a
  # session the log has no record of starting, and never for ourselves.
  if [[ -n "$PREV_SESSION_ID" && "$PREV_SESSION_ID" != "$SESSION_ID" ]] \
     && declare -F agent_session_has_start >/dev/null 2>&1; then
    if agent_session_has_start "$PREV_SESSION_ID" \
       && ! agent_session_has_end "$PREV_SESSION_ID"; then
      # The timestamp is this moment, not the real end — say so in the record
      # rather than implying a precision the backfill does not have.
      AGENT_SESSION_ID="$PREV_SESSION_ID" _agent_log "INFO" "SESSION_END" \
        "Session ended (backfilled at next session start; exact end time unknown)" \
        "backfilled_by=${SESSION_ID}" || true
    fi
  fi

  agent_session_start "Session started by $SESSION_USER on branch $BRANCH_NAME"
fi

# --- Build context output ---
CONTEXT="Session branch: $BRANCH_NAME\nUser: $SESSION_USER\nAudit logging: active (logs/audit/$SESSION_USER/)\n"
CONTEXT+="${BRANCH_WARNING}"
# Silent when the clone is current and origin was reached — the common case
# should cost nothing. Only speaks when there is something to act on.
CONTEXT+="${STALE_WARNING}"

# Unregistered-and-ambiguous identity warning. Silent when the person is
# registered, or when nothing about their setup could resolve differently.
if declare -F hook_identity_warning >/dev/null 2>&1; then
  _IDW="$(hook_identity_warning "$SESSION_USER" 2>/dev/null || echo "")"
  [[ -n "$_IDW" ]] && CONTEXT+="\n${_IDW}\n"
fi

# Agent registry summary
if [[ -f "$PROJECT_DIR/agents/registry.json" ]]; then
  AGENT_COUNT="$(jq 'length // (.agents | length) // 0' "$PROJECT_DIR/agents/registry.json" 2>/dev/null || echo "0")"
  CONTEXT+="Agent registry: $AGENT_COUNT agents available.\n"
fi

# --- Inject cross-session facts cache (from log repo) ---
FACTS_FILE="${LOG_REPO_DIR:-$PROJECT_DIR}/notes/$SESSION_USER/facts.md"
if [[ -f "$FACTS_FILE" ]] && [[ -s "$FACTS_FILE" ]]; then
  FACTS_LINES="$(wc -l < "$FACTS_FILE")"
  CONTEXT+="\nCROSS-SESSION FACTS ($FACTS_LINES lines loaded from notes/$SESSION_USER/facts.md):\n"
  CONTEXT+="$(cat "$FACTS_FILE")\n"
fi


# No engine-adapter regeneration happens here any more.
#
# .claude/ is tracked in git — skills, commands and settings are ordinary files
# that `git clone` and `git pull` deliver. There is nothing to generate, nothing
# to drift, and no reason to ask anyone to restart a session for a new skill.
#
# What used to be here: a check that regenerated .claude/skills/ only when the
# directory was MISSING ENTIRELY. Anyone who had set the project up once kept
# that directory forever, so the check passed on every later session and their
# skill set froze. A skill added to git reached nobody. The fix is not a better
# check — it is not having a generated layer.

# --- Missing child repo detection ---
# Checked unconditionally, not only on a fresh clone. repos/<log-repo>/ is
# gitignored by the root repo, so when it is absent a write to
# repos/<log-repo>/logs/... lands in an ordinary untracked directory: the write
# succeeds, push-logs.sh finds nothing to push, and the session's record exists
# in no repository at all. This warning is the only thing between that and
# silent loss. Child repos are NOT cloned here — that needs network and
# credentials and would risk this hook's timeout.
MISSING_REPOS=""
if [[ -f "$PROJECT_DIR/repos/repos.json" ]] && command -v jq &>/dev/null; then
    while IFS= read -r _repo_name; do
        [[ -n "$_repo_name" ]] || continue
        [[ -d "$PROJECT_DIR/repos/$_repo_name/.git" ]] || MISSING_REPOS+=" $_repo_name"
    done < <(jq -r '.repos[]? | select(.clone_url != null and .clone_url != "") | .name' \
                "$PROJECT_DIR/repos/repos.json" 2>/dev/null || true)
fi
if [[ -n "$MISSING_REPOS" ]]; then
    CONTEXT+="\nCHILD REPO(S) NOT CLONED:${MISSING_REPOS}\n"
    CONTEXT+="Anything written under repos/<name>/ will be saved to an untracked directory and pushed nowhere.\n"
    CONTEXT+="Do not run /wrap-up until this is fixed. Run: bash scripts/bootstrap.sh\n"
fi

# --- Guided init detection ---
if [[ -f "$PROJECT_DIR/.needs-init" ]]; then
  STEPS="$(jq -r '.steps_remaining | join(", ")' "$PROJECT_DIR/.needs-init" 2>/dev/null || echo "unknown")"
  CONTEXT+="This project needs initial setup. Remaining steps: $STEPS\n"
  CONTEXT+="Run the init-wizard skill to complete guided setup.\n"
fi

# --- Stale wiki detection (scan log repo sources) ---
if [[ -f "$PROJECT_DIR/knowledge/research/.last_compile" ]]; then
  _LOG_DIR="${LOG_REPO_DIR:-$PROJECT_DIR}"
  NEWEST_SOURCE="$(find "$_LOG_DIR/logs/progress" "$_LOG_DIR/notes" -name '*.md' -newer "$PROJECT_DIR/knowledge/research/.last_compile" 2>/dev/null | head -1)"
  if [[ -n "$NEWEST_SOURCE" ]]; then
    CONTEXT+="Knowledge base may be stale. Run /project-wiki compile to update.\n"
  fi
fi

# --- Structural invariant check ---
if [[ -x "$PROJECT_DIR/scripts/validate/validate_agents_structure.py" ]]; then
  if ! python3 "$PROJECT_DIR/scripts/validate/validate_agents_structure.py" &>/dev/null; then
    CONTEXT+="\nWARNING: Agent structure validation has failures. Run: python3 scripts/validate/validate_agents_structure.py\n"
  fi
fi

echo -e "$CONTEXT"
