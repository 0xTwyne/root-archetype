#!/bin/bash
# Test matrix for check_clone_destination.sh
#
# Run from anywhere:  bash scripts/hooks/tests/test_clone_destination.sh
# Exit 0 = every case behaved; exit 1 = at least one regression.
#
# The guard is only worth having if it does not misfire: a PreToolUse hook on
# Bash that refuses ordinary commands gets switched off, and then it protects
# nothing. So the ALLOW half of this matrix matters at least as much as the
# BLOCK half, and deliberately includes the -o collisions (grep, find, gcc,
# sort) that a naive output-flag parser would trip on.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
HOOK="$ROOT/scripts/hooks/check_clone_destination.sh"
cd "$ROOT" || exit 1
export CLAUDE_PROJECT_DIR="$ROOT"

pass=0
fail=0

check() {
    local want="$1" cmd="$2" out rc
    out=$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' \
          | timeout 10 bash "$HOOK" 2>&1) && rc=0 || rc=$?
    if [[ "$rc" == "$want" ]]; then
        pass=$((pass + 1))
        printf '  ok   [%s] %s\n' "$want" "$cmd"
    else
        fail=$((fail + 1))
        printf '  FAIL want=%s got=%s  %s\n       %s\n' \
               "$want" "$rc" "$cmd" "$(echo "$out" | head -2 | tr '\n' ' ')"
    fi
}

echo "=== MUST BLOCK (destination outside the project) ==="
check 2 'git clone https://github.com/acme/widget ../widget-clean'
check 2 'git clone https://github.com/x/y.git /home/someone/dev/y'
check 2 'cd /home/someone && git clone https://github.com/x/y.git y'
check 2 'cd .. && git clone https://github.com/x/y.git escape'
check 2 'git -C /home/someone clone https://github.com/x/y.git y'
check 2 'git clone -o upstream https://github.com/x/y.git ../out'
check 2 'git clone --depth=1 https://github.com/x/y.git ../bad'
check 2 'git clone -b main --depth 1 https://github.com/x/y.git ../bad2'
check 2 'git worktree add -b br ../wt'
check 2 "git clone https://github.com/x/y.git ${ROOT}-evil/x"
check 2 'git clone https://github.com/x/y.git tmp/../../escape'
check 2 'git clone https://github.com/x/y.git "../my dir"'
check 2 'cd /tmp; git clone https://github.com/x/y.git y'
check 2 'git clone git@github.com:x/y.git ~/y'

echo "=== MUST ALLOW (inside the project, or not a clone at all) ==="
check 0 'git clone https://github.com/acme/widget repos/widget'
check 0 'git clone https://github.com/x/y.git tmp/y-scratch'
check 0 'git clone https://github.com/x/y.git'
check 0 'git clone -b main --depth 1 https://github.com/x/y.git tmp/ok'
check 0 'git clone https://github.com/x/y.git ./tmp/../repos/ok'
check 0 'git worktree add /tmp/claude-1001/x/scratchpad/wt -b feat origin/main'
check 0 'git worktree add tmp/wt -b feat origin/main'
check 0 'git worktree list'
check 0 'git worktree remove /tmp/claude-1001/x/scratchpad/wt --force'
check 0 'grep -o "pattern" file.txt'
check 0 'gcc -o /usr/local/bin/thing thing.c'
check 0 'git status && git log --oneline -3'
check 0 'echo "clone the worktree"'
check 0 'find . -name "*.sh" -o -name "*.py"'
check 0 'sort -o /var/tmp/out.txt in.txt'
check 0 'python3 run.py --output ../results.json'

echo "=== VARIABLES (regression: the guard once blocked its own author) ==="
# An assignment made in the same command must be expanded, not read literally.
check 0 'WT=/tmp/claude-1001/x/scratchpad/wt; git worktree add "$WT" branch'
check 0 'WT=/tmp/claude-1001/x/scratchpad/wt && git worktree add ${WT} branch'
check 0 'D=tmp/scratch; git clone https://github.com/x/y.git $D'
check 2 'D=../outside; git clone https://github.com/x/y.git $D'
# Genuinely unresolvable (environment, not assigned here): allow with a note on
# stderr rather than refuse on a guess.
check 0 'git worktree add "$SOME_ENV_DIR" branch'
check 0 'git clone https://github.com/x/y.git "$UNSET_TARGET"'

echo
echo "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
