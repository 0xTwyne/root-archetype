#!/bin/bash
# Regression matrix for "log data never lands in the root repo".
#
# Run from anywhere:  bash scripts/hooks/tests/test_root_write_isolation.sh
# Exit 0 = every case behaved; exit 1 = at least one regression.
#
# WHAT WENT WRONG
#
#   In split mode (a declared log repo), three separate paths still put log
#   data into the ROOT repo, recreating the four-month silent fork that
#   log-repo.sh's no-fallback contract exists to prevent:
#
#     * post-tool-use-audit.sh had an explicit two-stage fallback: if the
#       log-repo write failed, the audit record was appended under
#       <root>/logs/audit/ — a trail that exists in the log repo nowhere.
#     * agent_log.sh defaulted to <git toplevel>/logs whenever LOG_REPO_DIR
#       was not already exported, so any direct invocation (cron, manual
#       script) appended to <root>/logs/agent_audit.log.
#     * pre-edit-guard.sh only WARNED on root-repo writes under logs/ and
#       notes/, and exempted the shared files (INDEX.md, notes/handoffs/*)
#       entirely — and a warned write still happens.
#
# SAFETY
#
#   Every case runs in a throwaway project dir. Nothing touches a real repo.
#   The audit hook needs no git repo at all; agent_log.sh gets a sandbox git
#   toplevel so its resolver has something safe to resolve against.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Sandbox project with a declared, present log repo (split mode).
new_split_sandbox() {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/scripts/hooks/lib" "$d/scripts/utils" "$d/scripts/lib" \
             "$d/repos/proj-knowledge/logs" "$d/logs"
    cp "$ROOT/scripts/hooks/post-tool-use-audit.sh" "$d/scripts/hooks/"
    cp "$ROOT/scripts/hooks/pre-edit-guard.sh"      "$d/scripts/hooks/"
    cp "$ROOT/scripts/hooks/lib/"*.sh               "$d/scripts/hooks/lib/" 2>/dev/null
    cp "$ROOT/scripts/utils/agent_log.sh"           "$d/scripts/utils/"
    cp "$ROOT/scripts/lib/"*.sh                     "$d/scripts/lib/" 2>/dev/null
    jq -cn '{log_repo_name:"proj-knowledge"}' > "$d/.archetype-manifest.json"
    jq -cn '{session_id:"sess-iso", user:"tester", branch:"session/test"}' \
        > "$d/.session-identity"
    printf '%s\n' "$d"
}

audit_input() {  # tool-call payload for the PostToolUse hook
    jq -cn '{tool_name:"Bash", tool_input:{command:"true"}}'
}

edit_input() {  # $1=file_path — payload for the PreToolUse guard
    jq -cn --arg f "$1" '{tool_name:"Write", tool_input:{file_path:$f, content:"x"}}'
}

echo "=== 1. audit record lands in the LOG repo, and only there ==="
D="$(new_split_sandbox)"
audit_input | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/post-tool-use-audit.sh" >/dev/null 2>&1
in_log="$(find "$D/repos/proj-knowledge/logs/audit" -name '*.jsonl' 2>/dev/null | wc -l)"
in_root="$(find "$D/logs" -name '*.jsonl' 2>/dev/null | wc -l)"
[[ "$in_log" == "1" && "$in_root" == "0" ]] && ok "log repo x1, root x0" \
    || bad "log repo x$in_log, root x$in_root (want 1/0)"
rm -rf "$D"

echo "=== 2. unwritable log repo: record DROPPED, never redirected to root ==="
D="$(new_split_sandbox)"
chmod -w "$D/repos/proj-knowledge/logs"
err="$(audit_input | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/post-tool-use-audit.sh" 2>&1 >/dev/null)"
chmod +w "$D/repos/proj-knowledge/logs"
in_root="$(find "$D/logs" -name '*.jsonl' 2>/dev/null | wc -l)"
if [[ "$in_root" == "0" ]]; then
    ok "no root file created"
else
    bad "root got x$in_root files — the fallback is back" "$(find "$D/logs" -name '*.jsonl')"
fi
[[ "$err" == *"could not write audit record"* ]] && ok "failure is loud on stderr" \
    || bad "write failure was silent" "$err"
rm -rf "$D"

echo "=== 3. single-repo mode: root IS the log location, write is legitimate ==="
D="$(new_split_sandbox)"
rm "$D/.archetype-manifest.json"          # no declared log repo
audit_input | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/post-tool-use-audit.sh" >/dev/null 2>&1
in_root="$(find "$D/logs" -name '*.jsonl' 2>/dev/null | wc -l)"
[[ "$in_root" == "1" ]] && ok "root write allowed with no log repo declared" \
    || bad "root x$in_root (want 1)"
rm -rf "$D"

echo "=== 4. agent_log.sh resolves the log repo even when LOG_REPO_DIR is unset ==="
D="$(new_split_sandbox)"
( cd "$D" && git init -q . )              # give the resolver a git toplevel
( cd "$D" && bash -c 'source scripts/utils/agent_log.sh; agent_observe "direct call"' )
in_log="$([[ -f "$D/repos/proj-knowledge/logs/agent_audit.log" ]] && echo 1 || echo 0)"
in_root="$([[ -f "$D/logs/agent_audit.log" ]] && echo 1 || echo 0)"
[[ "$in_log" == "1" && "$in_root" == "0" ]] && ok "direct invocation wrote to the log repo" \
    || bad "log repo x$in_log root x$in_root (want 1/0)"
rm -rf "$D"

echo "=== 5. guard BLOCKS root stub writes in split mode ==="
D="$(new_split_sandbox)"
for p in "logs/progress/tester/x.md" "notes/tester/handoffs/active/x.md" \
         "notes/handoffs/INDEX.md" "logs/progress/INDEX.md" \
         "knowledge/taxonomy.yaml" "knowledge/research/deep-dives/x.md"; do
    edit_input "$D/$p" | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/pre-edit-guard.sh" >/dev/null 2>&1
    rc=$?
    [[ "$rc" == "2" ]] && ok "root $p blocked (exit 2)" \
        || bad "root $p NOT blocked (exit $rc)"
done
rm -rf "$D"

echo "=== 6. guard allows the same writes in the LOG repo (own user) ==="
D="$(new_split_sandbox)"
for p in "logs/progress/tester/x.md" "notes/tester/handoffs/active/x.md" \
         "notes/handoffs/INDEX.md"; do
    edit_input "$D/repos/proj-knowledge/$p" | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/pre-edit-guard.sh" >/dev/null 2>&1
    rc=$?
    [[ "$rc" == "0" ]] && ok "log repo $p allowed" \
        || bad "log repo $p blocked (exit $rc)"
done

echo "=== 7. cross-user ownership check still holds in the log repo ==="
edit_input "$D/repos/proj-knowledge/logs/progress/someone-else/x.md" \
    | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/pre-edit-guard.sh" >/dev/null 2>&1
rc=$?
[[ "$rc" == "2" ]] && ok "cross-user write blocked" || bad "cross-user write allowed (exit $rc)"
rm -rf "$D"

echo "=== 8. single-repo mode: root logs/ writes are not blocked ==="
D="$(new_split_sandbox)"
rm "$D/.archetype-manifest.json"
for p in "logs/progress/tester/x.md" "knowledge/taxonomy.yaml"; do
    edit_input "$D/$p" | CLAUDE_PROJECT_DIR="$D" bash "$D/scripts/hooks/pre-edit-guard.sh" >/dev/null 2>&1
    rc=$?
    [[ "$rc" == "0" ]] && ok "single-repo root $p allowed" || bad "single-repo $p blocked (exit $rc)"
done
rm -rf "$D"

echo "=== 9. init copy-mode exclusion covers the instance-data leak ==="
REGEX="$(grep -o "grep -zvE '[^']*'" "$ROOT/init-project.sh" | sed "s/grep -zvE '//;s/'\$//")"
if [[ -z "$REGEX" ]]; then
    bad "could not extract the exclusion regex from init-project.sh"
else
    for leak in "knowledge/wiki/skills-framework.md" \
                "knowledge/research/deep-dives/some-topic.md" \
                "knowledge/research/intake_index.yaml" \
                "knowledge/taxonomy.yaml" \
                ".promoted-sources" "notes/handoffs/INDEX.md" \
                "logs/progress/someone/2026-01-01.md" "logs/audit/someone/x.jsonl"; do
        if printf '%s' "$leak" | grep -qE "$REGEX"; then
            ok "excludes $leak"
        else
            bad "COPIES $leak into spawned projects"
        fi
    done
    # taxonomy.yaml is excluded WITH the rest of knowledge/ since 2026-08-29 —
    # the project's copy is seeded into the knowledge repo from templates/.
    for keep in "templates/log-repo/wiki/taxonomy.yaml" \
                "templates/log-repo/wiki/research/intake_index.yaml" \
                "scripts/hooks/session-end.sh" "AGENT.md"; do
        if printf '%s' "$keep" | grep -qE "$REGEX"; then
            bad "wrongly excludes $keep"
        else
            ok "keeps $keep"
        fi
    done
fi

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
