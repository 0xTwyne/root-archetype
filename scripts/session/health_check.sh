#!/bin/bash
set -euo pipefail

# System health check — pre-session diagnostics
# Returns 0 if all critical checks pass, 1 if any fail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"

PASS=0
WARN=0
FAIL=0

# Note: `((VAR++))` returns exit status 1 when VAR is 0 (post-increment yields
# the old value), which aborts the script under `set -e`. Use arithmetic
# assignment instead.
check_pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
check_warn() { echo "  WARN: $1"; WARN=$((WARN + 1)); }
check_fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Health Check: $(basename "$REPO_ROOT") ==="

# --- Git status ---
if git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
    check_pass "Git repository valid"
else
    check_fail "Not a git repository"
fi

# --- Required directories ---
for dir in agents scripts knowledge; do
    if [[ -d "${REPO_ROOT}/${dir}" ]]; then
        check_pass "Directory exists: ${dir}"
    else
        check_fail "Missing directory: ${dir}"
    fi
done

# --- Knowledge repo ---
if [[ -f "${REPO_ROOT}/scripts/hooks/lib/hook-utils.sh" ]]; then
    PROJECT_DIR="$REPO_ROOT"
    source "${REPO_ROOT}/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
    hook_resolve_log_repo 2>/dev/null || true
fi

if [[ -n "${LOG_REPO_DIR:-}" && "$LOG_REPO_DIR" != "$REPO_ROOT" ]]; then
    if [[ -d "$LOG_REPO_DIR/.git" ]]; then
        check_pass "Knowledge repo reachable: $(basename "$LOG_REPO_DIR")"
        for dir in logs notes; do
            if [[ -d "$LOG_REPO_DIR/$dir" ]]; then
                check_pass "Knowledge repo directory: ${dir}"
            else
                check_warn "Knowledge repo missing: ${dir}"
            fi
        done
    else
        check_fail "Knowledge repo not a git repo: $LOG_REPO_DIR"
    fi
else
    check_warn "No separate knowledge repo configured (using root repo for logs)"
fi

# --- Hooks configured ---
SETTINGS="${REPO_ROOT}/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
    HOOK_COUNT=$(jq '.hooks.PreToolUse | length' "$SETTINGS" 2>/dev/null || echo 0)
    if [[ "$HOOK_COUNT" -gt 0 ]]; then
        check_pass "Hooks configured (${HOOK_COUNT} matchers)"
    else
        check_warn "No hooks configured"
    fi
else
    check_warn "No .claude/settings.json"
fi

# --- Agent files valid ---
if python3 "${REPO_ROOT}/scripts/validate/validate_agents_structure.py" &>/dev/null; then
    check_pass "Agent structure valid"
else
    check_warn "Agent structure validation failed"
fi

# --- Disk space ---
AVAIL_GB=$(df -BG "${REPO_ROOT}" | tail -1 | awk '{print $4}' | tr -d 'G')
if [[ "$AVAIL_GB" -gt 10 ]]; then
    check_pass "Disk space: ${AVAIL_GB}GB available"
else
    check_warn "Low disk space: ${AVAIL_GB}GB available"
fi

# --- GitHub CLI version ---
#
# The Dockerfile now installs gh from cli.github.com, but an image built before
# that change still carries the distro package (2.46.0, Jan 2025). That version
# queries a GraphQL field GitHub has retired, so EVERY `gh pr edit` fails --
# and fails quietly enough to look like it worked. Warn rather than fail: gh
# create/view/merge/checks and `gh api` are all fine, so a stale gh is a
# nuisance, not a broken environment.
#
# 2.55 is a conservative floor; 2.46.0 is the version measured broken.
if command -v gh >/dev/null 2>&1; then
    # The trailing `head -1` is not redundant: `gh --version` prints
    # "gh version 2.46.0 (2025-01-13 Ubuntu 2.46.0-3)", grep -oE emits EVERY
    # match, and without it GH_VER becomes the two-line string "2.46.0\n2.46.0"
    # -- which then splits the warning across two lines. Same shape as the
    # "HEAD\nunknown" provenance bug fixed in agent_log.sh.
    GH_VER="$(gh --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ -n "$GH_VER" ]]; then
        GH_MAJ="${GH_VER%%.*}"; GH_REST="${GH_VER#*.}"; GH_MIN="${GH_REST%%.*}"
        if [[ "$GH_MAJ" -lt 2 || ( "$GH_MAJ" -eq 2 && "$GH_MIN" -lt 55 ) ]]; then
            check_warn "gh ${GH_VER} is too old — 'gh pr edit' fails on every repo (retired Projects GraphQL field), and fails quietly. Rebuild the devcontainer, or use: gh api -X PATCH repos/OWNER/REPO/pulls/N -F body=@file"
        else
            check_pass "gh ${GH_VER}"
        fi
    fi
fi

# --- Summary ---
echo ""
echo "Results: ${PASS} pass, ${WARN} warn, ${FAIL} fail"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
