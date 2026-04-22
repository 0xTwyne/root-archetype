#!/bin/bash
# Agent audit logging — append-only JSONL with session tracking
# Usage: source scripts/utils/agent_log.sh

# Resolve log directory: prefer log repo if available, fall back to root repo
_AGENT_LOG_DIR="${AGENT_LOG_DIR:-${LOG_REPO_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}/logs}"
_AGENT_LOG_FILE="${_AGENT_LOG_DIR}/agent_audit.log"
_AGENT_SESSION_FILE="${_AGENT_LOG_DIR}/.current_session"
_AGENT_SESSION_STALE_HOURS=4

mkdir -p "$_AGENT_LOG_DIR"

_agent_session_id() {
    # Return current session ID, creating if stale or missing
    if [[ -f "$_AGENT_SESSION_FILE" ]]; then
        local age_s
        age_s=$(( $(date +%s) - $(stat -c %Y "$_AGENT_SESSION_FILE" 2>/dev/null || echo 0) ))
        if [[ $age_s -lt $(( _AGENT_SESSION_STALE_HOURS * 3600 )) ]]; then
            cat "$_AGENT_SESSION_FILE"
            return
        fi
    fi
    local sid="ses_$(date +%Y%m%d_%H%M%S)_$$"
    echo "$sid" > "$_AGENT_SESSION_FILE"
    echo "$sid"
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
    echo "$json" >> "$_AGENT_LOG_FILE"
}

# --- Public API ---

agent_session_start() { _agent_log "INFO" "SESSION_START" "${1:-Session started}"; }
agent_session_end()   { _agent_log "INFO" "SESSION_END" "${1:-Session ended}"; rm -f "$_AGENT_SESSION_FILE"; }

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
