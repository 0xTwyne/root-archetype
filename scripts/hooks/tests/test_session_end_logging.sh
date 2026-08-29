#!/bin/bash
# Regression matrix for "SessionEnd always writes SESSION_END".
#
# Run from anywhere:  bash scripts/hooks/tests/test_session_end_logging.sh
# Exit 0 = every case behaved; exit 1 = at least one regression.
#
# WHAT WENT WRONG
#
#   A project generated from this archetype showed 222 SESSION_START against
#   202 SESSION_END, which reads as ~20 sessions dying before their hook ran.
#   It was not. Grouping by session id gave 23 STARTs with no END *and 21 ENDs
#   with no START* — near-symmetric, the signature of ends filed under the wrong
#   name rather than ends never written. 19 ids carried more than one
#   SESSION_START; one carried four.
#
#   Cause: the audit session id came from logs/.current_session, a single shared
#   mutable file with a 4-hour reuse window. Two overlapping sessions read the
#   same file and shared an id; a session whose end found the file deleted (by a
#   concurrent session's end) minted a fresh id and filed SESSION_END under that.
#
#   agent_log.sh is inherited verbatim by every project generated from this
#   archetype, so the defect was latent in all of them.
#
#   Case 1 additionally locks in a property this archetype already has and
#   should keep: the hooks resolve their own location from BASH_SOURCE and do
#   NOT gate on a relative path. A downstream copy that had grown
#    exited 0 from any
#   other working directory, writing nothing at all.
#
# SAFETY
#
#   Every case runs against a throwaway project dir with AGENT_LOG_DIR pointed
#   into it. Nothing here touches the real log repo, creates a branch, or
#   pushes. push-logs.sh is deliberately NOT copied into the sandbox, so the
#   hook's push block is skipped by its own `[[ -x ]]` test.
#
# NOT COVERED
#
#   The wiring in session-start.sh that calls the backfill. Running that hook
#   for real rewrites .session-identity and checks out a branch, so it is tested
#   by its predicates (has_start / has_end) rather than end-to-end. Those
#   predicates are the part that carries the logic.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Build a sandbox project: hooks + the logging lib, no push-logs.
new_sandbox() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/scripts/hooks/lib" "$d/scripts/utils" "$d/scripts/lib" "$d/logs"
    cp "$ROOT/scripts/hooks/session-end.sh"   "$d/scripts/hooks/"
    cp "$ROOT/scripts/hooks/lib/"*.sh         "$d/scripts/hooks/lib/" 2>/dev/null
    cp "$ROOT/scripts/utils/agent_log.sh"     "$d/scripts/utils/"
    cp "$ROOT/scripts/lib/"*.sh               "$d/scripts/lib/" 2>/dev/null
    printf '%s\n' "$d"
}

identity() {  # $1=dir $2=session_id
    jq -cn --arg s "$2" '{session_id:$s, user:"tester", branch:"session/test", root_repo:"sandbox"}' \
        > "$1/.session-identity"
}

count_cat() {  # $1=logfile $2=session_id $3=cat
    [[ -f "$1" ]] || { echo 0; return; }
    # `grep -c` prints 0 AND exits 1 on no match, so a trailing `|| echo 0`
    # emits the count twice — "x0\n0" in a failure message, and a two-line
    # string in any [[ ]] comparison. Capture, then default.
    local n
    n="$(grep -F "\"session\":\"$2\"" "$1" 2>/dev/null | grep -cF "\"cat\":\"$3\"")" || n=0
    printf '%s\n' "${n:-0}"
}

echo "=== 1. SESSION_END is written when the hook runs from a FOREIGN cwd ==="
# Guards against anyone reintroducing a relative-path gate at the top of the hook.
D="$(new_sandbox)"; identity "$D" "sess-foreign-cwd"
( cd /tmp && CLAUDE_PROJECT_DIR="$D" AGENT_LOG_DIR="$D/logs" \
    bash "$D/scripts/hooks/session-end.sh" >/dev/null 2>&1 )
n="$(count_cat "$D/logs/agent_audit.log" "sess-foreign-cwd" "SESSION_END")"
[[ "$n" == "1" ]] && ok "cwd=/tmp still logs SESSION_END" \
                  || bad "cwd=/tmp logged SESSION_END x$n (want 1)" "$(ls "$D/logs" 2>&1)"
rm -rf "$D"

echo "=== 2. SESSION_END is written when the project dir is the cwd ==="
D="$(new_sandbox)"; identity "$D" "sess-home-cwd"
( cd "$D" && CLAUDE_PROJECT_DIR="$D" AGENT_LOG_DIR="$D/logs" \
    bash "$D/scripts/hooks/session-end.sh" >/dev/null 2>&1 )
n="$(count_cat "$D/logs/agent_audit.log" "sess-home-cwd" "SESSION_END")"
[[ "$n" == "1" ]] && ok "cwd=project logs SESSION_END" || bad "logged x$n (want 1)"
rm -rf "$D"

echo "=== 3. END is filed under the REAL session id, pairing with its START ==="
D="$(new_sandbox)"; identity "$D" "sess-pairing"
export AGENT_LOG_DIR="$D/logs"; export CLAUDE_PROJECT_DIR="$D"
( source "$D/scripts/utils/agent_log.sh"; SESSION_ID="sess-pairing" agent_session_start "start" )
bash "$D/scripts/hooks/session-end.sh" >/dev/null 2>&1
s_n="$(count_cat "$D/logs/agent_audit.log" "sess-pairing" "SESSION_START")"
e_n="$(count_cat "$D/logs/agent_audit.log" "sess-pairing" "SESSION_END")"
[[ "$s_n" == "1" && "$e_n" == "1" ]] && ok "START/END both under sess-pairing" \
    || bad "START x$s_n END x$e_n (want 1/1)" "$(cat "$D/logs/agent_audit.log")"
unset AGENT_LOG_DIR CLAUDE_PROJECT_DIR
rm -rf "$D"

echo "=== 4. A deleted .current_session does NOT mint a fresh id at end time ==="
# This is the exact mechanism behind the 21 orphan ENDs.
D="$(new_sandbox)"; identity "$D" "sess-marker-gone"
export AGENT_LOG_DIR="$D/logs"; export CLAUDE_PROJECT_DIR="$D"
( source "$D/scripts/utils/agent_log.sh"; SESSION_ID="sess-marker-gone" agent_session_start "start" )
rm -f "$D/logs/.current_session"          # simulate a peer session's end
bash "$D/scripts/hooks/session-end.sh" >/dev/null 2>&1
e_n="$(count_cat "$D/logs/agent_audit.log" "sess-marker-gone" "SESSION_END")"
orphan="$(grep -cF '"cat":"SESSION_END"' "$D/logs/agent_audit.log" 2>/dev/null || echo 0)"
[[ "$e_n" == "1" && "$orphan" == "1" ]] && ok "END stayed on the real id; no stray id minted" \
    || bad "END on real id x$e_n, total ENDs $orphan (want 1/1)" "$(cat "$D/logs/agent_audit.log")"
unset AGENT_LOG_DIR CLAUDE_PROJECT_DIR
rm -rf "$D"

echo "=== 5. Concurrent sessions do NOT share one id ==="
# Two sessions inside the old 4-hour window collapsed onto a single id.
D="$(new_sandbox)"
export AGENT_LOG_DIR="$D/logs"
( source "$D/scripts/utils/agent_log.sh"; SESSION_ID="sess-A" agent_session_start "A" )
( source "$D/scripts/utils/agent_log.sh"; SESSION_ID="sess-B" agent_session_start "B" )
a="$(count_cat "$D/logs/agent_audit.log" "sess-A" "SESSION_START")"
b="$(count_cat "$D/logs/agent_audit.log" "sess-B" "SESSION_START")"
[[ "$a" == "1" && "$b" == "1" ]] && ok "two overlapping sessions kept distinct ids" \
    || bad "A x$a B x$b (want 1/1)" "$(cat "$D/logs/agent_audit.log")"
unset AGENT_LOG_DIR
rm -rf "$D"

echo "=== 6. agent_session_end is idempotent ==="
# A duplicated SessionEnd invocation must not manufacture a second session.
D="$(new_sandbox)"; identity "$D" "sess-twice"
export CLAUDE_PROJECT_DIR="$D"; export AGENT_LOG_DIR="$D/logs"
bash "$D/scripts/hooks/session-end.sh" >/dev/null 2>&1
bash "$D/scripts/hooks/session-end.sh" >/dev/null 2>&1
n="$(count_cat "$D/logs/agent_audit.log" "sess-twice" "SESSION_END")"
[[ "$n" == "1" ]] && ok "two invocations wrote one END" || bad "wrote x$n (want 1)"
unset CLAUDE_PROJECT_DIR AGENT_LOG_DIR
rm -rf "$D"

echo "=== 7. Backfill predicates ==="
D="$(new_sandbox)"
export AGENT_LOG_DIR="$D/logs"
source "$D/scripts/utils/agent_log.sh"

# Assert the predicates EXIST before asserting what they return. Without this,
# `agent_session_has_end X && bad || ok` scores an "ok" when the function is
# merely undefined — command-not-found is non-zero and reads identically to a
# correct negative. That is the same vacuous-check failure this whole change is
# about, reproduced inside its own test.
for _fn in agent_session_has_start agent_session_has_end; do
    if declare -F "$_fn" >/dev/null 2>&1; then
        ok "$_fn is defined"
    else
        bad "$_fn is NOT defined — the assertions below are meaningless"
    fi
done
SESSION_ID="sess-open"   agent_session_start "open session"
SESSION_ID="sess-closed" agent_session_start "closed session"
SESSION_ID="sess-closed" agent_session_end   "closed session"

agent_session_has_start "sess-open"   && ok "has_start true for a started session" \
    || bad "has_start false for sess-open"
agent_session_has_end   "sess-open"   && bad "has_end TRUE for an unclosed session" \
    || ok "has_end false for an unclosed session"
agent_session_has_end   "sess-closed" && ok "has_end true after agent_session_end" \
    || bad "has_end false for sess-closed"
agent_session_has_start "sess-never"  && bad "has_start TRUE for a session never seen" \
    || ok "has_start false for an unknown session — backfill cannot invent one"
unset AGENT_LOG_DIR
rm -rf "$D"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
