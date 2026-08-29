#!/bin/bash
# Agent audit logging — append-only JSONL with session tracking
# Usage: source scripts/utils/agent_log.sh

# Resolve log directory: prefer log repo if available, fall back to root repo

# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

_agent_log_default_dir() {
    local root; root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
    # Prefer an already-exported LOG_REPO_DIR (hooks resolve it before sourcing
    # this file); otherwise resolve it the same way they do. Falling back to
    # the git toplevel unconditionally is how the root repo accumulated audit
    # entries that existed in the log repo nowhere — the resolver only returns
    # the root when no log_repo_name is declared (genuine single-repo mode).
    if [[ -z "${LOG_REPO_DIR:-}" && -f "$root/scripts/hooks/lib/log-repo.sh" ]]; then
        # shellcheck source=/dev/null
        PROJECT_DIR="$root" source "$root/scripts/hooks/lib/log-repo.sh" 2>/dev/null || true
        hook_resolve_log_repo "$root" >/dev/null 2>&1 || true
    fi
    echo "${LOG_REPO_DIR:-$root}/logs"
}
_AGENT_LOG_DIR="${AGENT_LOG_DIR:-$(_agent_log_default_dir)}"
_AGENT_LOG_FILE="${_AGENT_LOG_DIR}/agent_audit.log"
_AGENT_SESSION_FILE="${_AGENT_LOG_DIR}/.current_session"
_AGENT_SESSION_STALE_HOURS=4

# Fail open with a diagnostic — an EACCES here (e.g. uid-mismatched dir
# ownership) must not abort a set -e caller like session-start.sh.
mkdir -p "$_AGENT_LOG_DIR" 2>/dev/null \
    || echo "agent_log: cannot create $_AGENT_LOG_DIR (check ownership/permissions)" >&2

_agent_session_id() {
    # The session field must be STABLE from SESSION_START to SESSION_END and
    # must identify exactly one session. Prefer the real session identity; the
    # shared marker file is a last resort.
    #
    # It used to come only from $_AGENT_SESSION_FILE — one shared, mutable file
    # with a 4-hour reuse window — which produced two distinct faults:
    #
    #   * Two sessions overlapping inside the window read the same file and
    #     logged under one id.
    #   * agent_session_end deletes the marker, so a session whose end found it
    #     missing (a concurrent session's end got there first) or stale minted a
    #     FRESH id and filed SESSION_END under it — an id with an END and no
    #     START, while its real id kept a START and no END.
    #
    # Downstream, that showed up as 222 SESSION_START against 202 SESSION_END,
    # which reads as sessions dying before their hook ran. It was not: grouping
    # by id gave 23 orphan STARTs AND 21 orphan ENDs. Orphans on both sides is
    # misfiling, not death. 19 ids carried more than one SESSION_START.
    #
    # .session-identity is the same source _agent_log already consults below for
    # repo/branch provenance, so this adds no new dependency.
    if [[ -n "${AGENT_SESSION_ID:-}" ]]; then
        printf '%s\n' "${AGENT_SESSION_ID}"
        return
    fi
    if [[ -n "${SESSION_ID:-}" && "${SESSION_ID}" != "unknown" ]]; then
        printf '%s\n' "${SESSION_ID}"
        return
    fi
    local _ident_root _sid
    _ident_root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
    if [[ -f "$_ident_root/.session-identity" ]]; then
        _sid="$(jq -r '.session_id // empty' "$_ident_root/.session-identity" 2>/dev/null | tr -d '\r' || true)"
        if [[ -n "$_sid" && "$_sid" != "null" ]]; then
            printf '%s\n' "$_sid"
            return
        fi
    fi
    # Fallback for callers outside a session (cron, manual scripts), where no
    # session identity exists. Same shape as before.
    if [[ -f "$_AGENT_SESSION_FILE" ]]; then
        local age_s
        age_s=$(( $(date +%s) - $(stat -c %Y "$_AGENT_SESSION_FILE" 2>/dev/null || echo 0) ))
        if [[ $age_s -lt $(( _AGENT_SESSION_STALE_HOURS * 3600 )) ]]; then
            cat "$_AGENT_SESSION_FILE"
            return
        fi
    fi
    local sid="ses_$(date +%Y%m%d_%H%M%S)_$$"
    echo "$sid" > "$_AGENT_SESSION_FILE" 2>/dev/null || true
    echo "$sid"
}

# True when the session id already carries an entry of the given category.
# Two greps rather than one fused literal: matching
# `"session":"X","level":"INFO","cat":"Y"` in one pattern silently depends on
# those keys staying adjacent and in that order. This file already emits eight
# fields and has gained some over time, so that assumption is a live hazard —
# a reordering would make the predicate answer "no" for every session and
# quietly invert both the idempotency and backfill guards.
_agent_session_has_cat() {
    local sid="$1" cat="$2"
    [[ -f "$_AGENT_LOG_FILE" ]] || return 1
    grep -F "\"session\":\"${sid}\"" "$_AGENT_LOG_FILE" 2>/dev/null \
        | grep -Fq "\"cat\":\"${cat}\""
}

# True when the given session id already has a SESSION_END in the audit log.
agent_session_has_end() {
    _agent_session_has_cat "${1:?agent_session_has_end requires a session id}" "SESSION_END"
}

# True when the given session id has a SESSION_START in the audit log.
agent_session_has_start() {
    _agent_session_has_cat "${1:?agent_session_has_start requires a session id}" "SESSION_START"
}

_agent_log() {
    local level="$1" category="$2" message="$3" details="${4:-}"
    local session
    session=$(_agent_session_id)
    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Resolve repo/branch provenance (cached per session)
    if [[ -z "${_AGENT_LOG_REPO:-}" ]]; then
        local _root
        _root="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
        if [[ -f "$_root/.session-identity" ]]; then
            _AGENT_LOG_REPO="$(jq -r '.root_repo // empty' "$_root/.session-identity" 2>/dev/null || echo "")"
            _AGENT_LOG_BRANCH="$(jq -r '.branch // empty' "$_root/.session-identity" 2>/dev/null || echo "")"
        fi
        _AGENT_LOG_REPO="${_AGENT_LOG_REPO:-$(basename "$_root")}"
        _AGENT_LOG_BRANCH="${_AGENT_LOG_BRANCH:-$(git -C "$_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")}"
    fi

    local json
    json=$(jq -nc \
        --arg ts "$ts" \
        --arg session "$session" \
        --arg level "$level" \
        --arg cat "$category" \
        --arg msg "$message" \
        --arg details "$details" \
        --arg repo "${_AGENT_LOG_REPO:-}" \
        --arg branch "${_AGENT_LOG_BRANCH:-}" \
        '{ts:$ts, session:$session, level:$level, cat:$cat, msg:$msg, details:$details, repo:$repo, branch:$branch}')
    echo "$json" >> "$_AGENT_LOG_FILE" 2>/dev/null \
        || echo "agent_log: cannot append to $_AGENT_LOG_FILE (check ownership/permissions)" >&2
}

# --- Public API ---

agent_session_start() { _agent_log "INFO" "SESSION_START" "${1:-Session started}"; }
# Idempotent: a second SESSION_END for a session that already has one would
# turn a duplicated hook invocation into a fake extra session. Returns 0 either
# way so a `set -e` caller (session-end.sh) can never abort on it.
agent_session_end() {
    local sid
    sid="$(_agent_session_id)"
    if agent_session_has_end "$sid"; then
        rm -f "$_AGENT_SESSION_FILE" 2>/dev/null || true
        return 0
    fi
    AGENT_SESSION_ID="$sid" _agent_log "INFO" "SESSION_END" "${1:-Session ended}" || true
    rm -f "$_AGENT_SESSION_FILE" 2>/dev/null || true
    return 0
}

agent_task_start()    { _agent_log "INFO" "TASK_START" "$1" "${2:-}"; }
agent_task_end()      { _agent_log "INFO" "TASK_END" "$1" "${2:-success}"; }

agent_cmd_intent()    { _agent_log "INFO" "CMD_INTENT" "$1" "${2:-}"; }
agent_cmd_result()    { _agent_log "INFO" "CMD_RESULT" "$1" "exit=${2:-0} ${3:-}"; }

agent_file_modify()   { _agent_log "INFO" "FILE_MODIFY" "$1" "action=${2:-edit} ${3:-}"; }
agent_decision()      { _agent_log "INFO" "DECISION" "$1" "${2:-}"; }
agent_warn()          { _agent_log "WARN" "WARNING" "$1" "${2:-}"; }
agent_error()         { _agent_log "ERROR" "ERROR" "$1" "${2:-}"; }
agent_observe()       { _agent_log "INFO" "OBSERVE" "$1" "${2:-}"; }

agent_rollback_info() {
    _agent_log "INFO" "ROLLBACK" "$1" "undo: $2"
}

agent_exec() {
    local reasoning="$1"
    shift
    agent_cmd_intent "$*" "$reasoning"
    local rc=0
    "$@" || rc=$?
    agent_cmd_result "$*" "$rc"
    return $rc
}

agent_log_tail() {
    local n="${1:-20}"
    tail -n "$n" "$_AGENT_LOG_FILE" 2>/dev/null | jq -r '"\(.ts) [\(.level)] \(.cat): \(.msg)"'
}

agent_log_session() {
    local session
    session=$(_agent_session_id)
    grep "\"session\":\"${session}\"" "$_AGENT_LOG_FILE" 2>/dev/null | jq -r '"\(.ts) [\(.level)] \(.cat): \(.msg)"'
}
