#!/bin/bash
set -euo pipefail

# Swarm recovery: health check and stale-state cleanup.
# Usage: scripts/utils/swarm_recover.sh [--dry-run]

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB_PATH="${REPO_ROOT}/swarm/coordinator.db"

echo "=== Swarm Recovery ==="

# --- Check database exists ---
if [[ ! -f "$DB_PATH" ]]; then
    echo "No coordinator database found at ${DB_PATH}"
    echo "Nothing to recover."
    exit 0
fi

# --- Check database integrity ---
echo "Checking database integrity..."
INTEGRITY=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>&1)
if [[ "$INTEGRITY" != "ok" ]]; then
    echo "ERROR: Database integrity check failed:"
    echo "$INTEGRITY"
    exit 1
fi
echo "  Database integrity: OK"

# --- Report current state ---
echo ""
echo "Current state:"
sqlite3 -header -column "$DB_PATH" "
    SELECT
        (SELECT COUNT(*) FROM agents) as total_agents,
        (SELECT COUNT(*) FROM agents WHERE last_heartbeat >= strftime('%s','now') - 120) as active_agents,
        (SELECT COUNT(*) FROM work_items WHERE status = 'pending') as pending_work,
        (SELECT COUNT(*) FROM work_items WHERE status = 'claimed') as claimed_work,
        (SELECT COUNT(*) FROM resource_locks) as held_locks;
"

# --- Detect stale claims ---
STALE_CLAIMS=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM work_items wi
    JOIN agents a ON wi.claimed_by = a.agent_id
    WHERE wi.status = 'claimed'
    AND a.last_heartbeat < strftime('%s','now') - 120;
")

# --- Detect expired locks ---
EXPIRED_LOCKS=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM resource_locks
    WHERE acquired_at + ttl_seconds < strftime('%s','now');
")

# --- Detect orphaned locks (holder agent doesn't exist) ---
ORPHAN_LOCKS=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM resource_locks rl
    LEFT JOIN agents a ON rl.holder = a.agent_id
    WHERE a.agent_id IS NULL;
")

echo ""
echo "Issues found:"
echo "  Stale claims:   ${STALE_CLAIMS}"
echo "  Expired locks:  ${EXPIRED_LOCKS}"
echo "  Orphan locks:   ${ORPHAN_LOCKS}"

TOTAL_ISSUES=$((STALE_CLAIMS + EXPIRED_LOCKS + ORPHAN_LOCKS))

if [[ $TOTAL_ISSUES -eq 0 ]]; then
    echo ""
    echo "No issues found. Swarm state is healthy."
    exit 0
fi

if $DRY_RUN; then
    echo ""
    echo "[dry-run] Would fix ${TOTAL_ISSUES} issues. Run without --dry-run to apply."
    exit 0
fi

# --- Fix stale claims ---
if [[ $STALE_CLAIMS -gt 0 ]]; then
    echo ""
    echo "Releasing ${STALE_CLAIMS} stale claims..."
    sqlite3 "$DB_PATH" "
        UPDATE work_items SET status = 'pending', claimed_by = NULL, claimed_at = NULL
        WHERE status = 'claimed' AND claimed_by IN (
            SELECT agent_id FROM agents WHERE last_heartbeat < strftime('%s','now') - 120
        );
    "
fi

# --- Fix expired locks ---
if [[ $EXPIRED_LOCKS -gt 0 ]]; then
    echo "Removing ${EXPIRED_LOCKS} expired locks..."
    sqlite3 "$DB_PATH" "
        DELETE FROM resource_locks WHERE acquired_at + ttl_seconds < strftime('%s','now');
    "
fi

# --- Fix orphan locks ---
if [[ $ORPHAN_LOCKS -gt 0 ]]; then
    echo "Removing ${ORPHAN_LOCKS} orphan locks..."
    sqlite3 "$DB_PATH" "
        DELETE FROM resource_locks WHERE holder NOT IN (SELECT agent_id FROM agents);
    "
fi

echo ""
echo "Recovery complete. Fixed ${TOTAL_ISSUES} issues."
