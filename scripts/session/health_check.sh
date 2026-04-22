#!/bin/bash
set -euo pipefail

# System health check — pre-session diagnostics
# Returns 0 if all critical checks pass, 1 if any fail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"

PASS=0
WARN=0
FAIL=0

check_pass() { echo "  PASS: $1"; ((PASS++)); }
check_warn() { echo "  WARN: $1"; ((WARN++)); }
check_fail() { echo "  FAIL: $1"; ((FAIL++)); }

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

# --- Log repo ---
if [[ -f "${REPO_ROOT}/scripts/hooks/lib/hook-utils.sh" ]]; then
    PROJECT_DIR="$REPO_ROOT"
    source "${REPO_ROOT}/scripts/hooks/lib/hook-utils.sh" 2>/dev/null || true
    hook_resolve_log_repo 2>/dev/null || true
fi

if [[ -n "${LOG_REPO_DIR:-}" && "$LOG_REPO_DIR" != "$REPO_ROOT" ]]; then
    if [[ -d "$LOG_REPO_DIR/.git" ]]; then
        check_pass "Log repo reachable: $(basename "$LOG_REPO_DIR")"
        for dir in logs notes; do
            if [[ -d "$LOG_REPO_DIR/$dir" ]]; then
                check_pass "Log repo directory: ${dir}"
            else
                check_warn "Log repo missing: ${dir}"
            fi
        done
    else
        check_fail "Log repo not a git repo: $LOG_REPO_DIR"
    fi
else
    check_warn "No separate log repo configured (using root repo for logs)"
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

# --- Summary ---
echo ""
echo "Results: ${PASS} pass, ${WARN} warn, ${FAIL} fail"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
