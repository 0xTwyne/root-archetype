#!/usr/bin/env bash
# test_maintainer_resolution.sh — who pre-edit-guard.sh treats as a maintainer.
#
# The guard decides this by resolving BOTH sides through the alias registry: the
# session's canonical user on one side, and the owner of each MAINTAINERS.json
# entry on the other. Two failure modes motivated that, and both are pinned here
# because both were live and neither looked wrong:
#
#   Wrongly granted. `git config user.email` is inherited from the container
#   image, so every collaborator in a shared devcontainer presents the same
#   address. A session belonging to someone else passed the maintainer check on
#   an address that was never theirs.
#
#   Wrongly blocked. A maintainer whose commits carry a GitHub noreply address
#   is not the string in MAINTAINERS.json, so the guard hard-blocked the
#   project maintainer out of scripts/hooks/ on his own machine.
#
# This is not authentication and these tests do not claim it is. Anyone who can
# run `git config`, `gh auth` or edit `.session-identity` can present as someone
# else, and the guard fails open on timeout by harness design. What is pinned
# here is that ACCIDENTS do not grant access.
#
# Builds its own throwaway project; touches nothing outside its temp dir.

set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

command -v jq >/dev/null 2>&1 || { echo "SKIP test_maintainer_resolution.sh (no jq)"; exit 0; }

mkdir -p "$SB/repos/kb" "$SB/repos/child"
cp -r "$REPO_ROOT/scripts" "$SB/scripts"

cat > "$SB/.archetype-manifest.json" <<'JSON'
{"log_repo_name": "kb", "template_values": {"PROJECT_NAME": "idsandbox"}}
JSON

cat > "$SB/MAINTAINERS.json" <<'JSON'
{
  "project": "idsandbox",
  "global_maintainers": ["ada@example.com", "unclaimed@example.com"],
  "repo_maintainers": {"child": ["grace@example.com"]}
}
JSON

git -C "$SB/repos/kb" init -q 2>/dev/null
cat > "$SB/repos/kb/identities.json" <<'JSON'
{"users": [
  {"canonical": "ada",   "aliases": ["AdaLovelace", "ada@example.com", "12345+ada@users.noreply.github.com"]},
  {"canonical": "grace", "aliases": ["GraceHopper", "grace@example.com"]}
]}
JSON

PASS=0; FAIL=0
run() { # run <label> <session_user> <git_email> <path> <expect>
  local label="$1" suser="$2" email="$3" path="$4" expect="$5" rc got
  printf '{"session_id":"t","user":"%s"}\n' "$suser" > "$SB/.session-identity"
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.email GIT_CONFIG_VALUE_0="$email" \
    CLAUDE_PROJECT_DIR="$SB" \
    bash "$SB/scripts/hooks/pre-edit-guard.sh" \
    <<< "$(jq -cn --arg p "$path" '{tool_input:{file_path:$p,content:"x"}}')" >/dev/null 2>&1
  rc=$?
  got="allow"; [[ $rc -eq 2 ]] && got="block"
  if [[ "$got" == "$expect" ]]; then
    PASS=$((PASS+1)); printf '  ok   %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf '  FAIL %s (got %s, want %s)\n' "$label" "$got" "$expect"
  fi
}

H="$SB/scripts/hooks/x.sh"
C="$SB/repos/child/CLAUDE.md"

echo "-- a maintainer is the person, not the e-mail --"
run "maintainer on the listed address"            ada   ada@example.com                        "$H" allow
run "maintainer on an unlisted registered alias"  ada   12345+ada@users.noreply.github.com     "$H" allow

echo "-- an inherited address grants nothing --"
run "other person, inherited maintainer address"  grace ada@example.com                        "$H" block
run "unregistered person, claimed address"        newbie ada@example.com                       "$H" block

echo "-- repo_maintainers is scoped to its repo --"
run "child maintainer on the child repo"          grace grace@example.com                      "$C" allow
run "child maintainer on root hooks"              grace grace@example.com                      "$H" block
run "global maintainer on the child repo"         ada   ada@example.com                        "$C" allow
run "stranger on the child repo"                  newbie newbie@example.com                    "$C" block

echo "-- day one, before anyone registers --"
run "unclaimed maintainer address still works"    newbie unclaimed@example.com                 "$H" allow
run "stranger"                                    newbie nobody@example.com                    "$H" block
run "empty git user.email"                        newbie ""                                    "$H" block

echo "-- unrelated paths are never touched --"
run "ordinary source file"                        newbie nobody@example.com "$SB/repos/child/src.py" allow
run "root README"                                 newbie nobody@example.com "$SB/README.md"          allow

echo ""
echo "=== $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
