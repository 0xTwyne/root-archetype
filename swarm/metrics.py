"""Swarm observability — metrics export, latency tracking, budget burn-rate.

Queries the coordinator's SQLite database to produce structured metrics
snapshots. Designed for integration with agent_log.sh audit trail.
"""

import json
import sqlite3
import statistics
import subprocess
import time
from pathlib import Path
from typing import Any

from swarm.constants import (
    SQLITE_CONNECT_TIMEOUT,
    SQLITE_BUSY_TIMEOUT,
    HEARTBEAT_STALE_SECONDS,
)


class SwarmMetrics:
    """Read-only metrics exporter for the swarm coordinator database."""

    def __init__(self, db_path: str | Path = "swarm/coordinator.db"):
        self.db_path = Path(db_path)

    def _conn(self) -> sqlite3.Connection:
        conn = sqlite3.connect(
            str(self.db_path),
            timeout=SQLITE_CONNECT_TIMEOUT,
        )
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT}")
        conn.execute("PRAGMA query_only=ON")
        conn.row_factory = sqlite3.Row
        return conn

    # ---- Work item latency ----

    def work_latency(self) -> dict[str, Any]:
        """Latency distributions for completed work items.

        Returns wait_time (submit→claim), exec_time (claim→complete),
        and total_time (submit→complete) with p50/p95/p99 percentiles.
        """
        conn = self._conn()
        try:
            rows = conn.execute(
                "SELECT created_at, claimed_at, completed_at "
                "FROM work_items WHERE status IN ('completed', 'failed') "
                "AND claimed_at IS NOT NULL AND completed_at IS NOT NULL"
            ).fetchall()
        finally:
            conn.close()

        if not rows:
            return {"count": 0, "wait_time": {}, "exec_time": {}, "total_time": {}}

        wait_times = [r["claimed_at"] - r["created_at"] for r in rows]
        exec_times = [r["completed_at"] - r["claimed_at"] for r in rows]
        total_times = [r["completed_at"] - r["created_at"] for r in rows]

        return {
            "count": len(rows),
            "wait_time": _percentiles(wait_times),
            "exec_time": _percentiles(exec_times),
            "total_time": _percentiles(total_times),
        }

    # ---- Queue depth over time ----

    def queue_counts(self) -> dict[str, int]:
        """Current counts by work item status."""
        conn = self._conn()
        try:
            rows = conn.execute(
                "SELECT status, COUNT(*) as cnt FROM work_items GROUP BY status"
            ).fetchall()
        finally:
            conn.close()
        return {r["status"]: r["cnt"] for r in rows}

    # ---- Budget burn-rate per agent ----

    def budget_burn_rate(self, window_seconds: float = 3600.0) -> list[dict[str, Any]]:
        """Budget consumption rate per agent over a time window.

        Returns each agent's total spend, spend within the window,
        burn rate (cost/hour), and remaining budget.
        """
        now = time.time()
        cutoff = now - window_seconds
        conn = self._conn()
        try:
            agents = conn.execute(
                "SELECT agent_id, name, role, budget_remaining FROM agents"
            ).fetchall()

            results = []
            for agent in agents:
                aid = agent["agent_id"]
                # Total spend
                total_row = conn.execute(
                    "SELECT COALESCE(SUM(cost), 0) as total FROM budget_ledger WHERE agent_id = ?",
                    (aid,),
                ).fetchone()
                # Window spend
                window_row = conn.execute(
                    "SELECT COALESCE(SUM(cost), 0) as total FROM budget_ledger "
                    "WHERE agent_id = ? AND timestamp >= ?",
                    (aid, cutoff),
                ).fetchone()
                # Spend by action type
                by_type = conn.execute(
                    "SELECT action_type, SUM(cost) as total FROM budget_ledger "
                    "WHERE agent_id = ? GROUP BY action_type ORDER BY total DESC",
                    (aid,),
                ).fetchall()

                window_spend = window_row["total"]
                burn_per_hour = (window_spend / window_seconds) * 3600 if window_seconds > 0 else 0

                results.append({
                    "agent_id": aid,
                    "name": agent["name"],
                    "role": agent["role"],
                    "budget_remaining": agent["budget_remaining"],
                    "total_spend": total_row["total"],
                    "window_spend": window_spend,
                    "window_seconds": window_seconds,
                    "burn_rate_per_hour": round(burn_per_hour, 4),
                    "by_action_type": {r["action_type"]: r["total"] for r in by_type},
                })
        finally:
            conn.close()
        return results

    # ---- Agent activity ----

    def agent_activity(self) -> list[dict[str, Any]]:
        """Per-agent work item counts and status."""
        now = time.time()
        stale_cutoff = now - HEARTBEAT_STALE_SECONDS
        conn = self._conn()
        try:
            agents = conn.execute("SELECT * FROM agents").fetchall()
            results = []
            for a in agents:
                aid = a["agent_id"]
                claimed = conn.execute(
                    "SELECT COUNT(*) as cnt FROM work_items WHERE claimed_by = ? AND status = 'claimed'",
                    (aid,),
                ).fetchone()["cnt"]
                completed = conn.execute(
                    "SELECT COUNT(*) as cnt FROM work_items WHERE claimed_by = ? AND status = 'completed'",
                    (aid,),
                ).fetchone()["cnt"]
                failed = conn.execute(
                    "SELECT COUNT(*) as cnt FROM work_items WHERE claimed_by = ? AND status = 'failed'",
                    (aid,),
                ).fetchone()["cnt"]
                results.append({
                    "agent_id": aid,
                    "name": a["name"],
                    "role": a["role"],
                    "active": a["last_heartbeat"] >= stale_cutoff,
                    "last_heartbeat": a["last_heartbeat"],
                    "work_claimed": claimed,
                    "work_completed": completed,
                    "work_failed": failed,
                    "budget_remaining": a["budget_remaining"],
                })
        finally:
            conn.close()
        return results

    # ---- Information gain accuracy ----

    def info_gain_accuracy(self) -> dict[str, Any]:
        """Compare predicted_info_value vs actual_info_gain for completed items."""
        conn = self._conn()
        try:
            rows = conn.execute(
                "SELECT predicted_info_value, actual_info_gain "
                "FROM work_items WHERE status = 'completed' "
                "AND actual_info_gain IS NOT NULL"
            ).fetchall()
        finally:
            conn.close()

        if not rows:
            return {"count": 0}

        errors = [r["actual_info_gain"] - r["predicted_info_value"] for r in rows]
        abs_errors = [abs(e) for e in errors]
        return {
            "count": len(rows),
            "mean_error": round(statistics.mean(errors), 4),
            "mean_abs_error": round(statistics.mean(abs_errors), 4),
            "predicted": _percentiles([r["predicted_info_value"] for r in rows]),
            "actual": _percentiles([r["actual_info_gain"] for r in rows]),
        }

    # ---- Lock contention ----

    def lock_status(self) -> dict[str, Any]:
        """Current lock state and contention indicators."""
        now = time.time()
        conn = self._conn()
        try:
            all_locks = conn.execute("SELECT * FROM resource_locks").fetchall()
        finally:
            conn.close()

        active = []
        expired = []
        for lock in all_locks:
            expires_at = lock["acquired_at"] + lock["ttl_seconds"]
            entry = {
                "resource_id": lock["resource_id"],
                "holder": lock["holder"],
                "held_seconds": round(now - lock["acquired_at"], 1),
                "ttl_seconds": lock["ttl_seconds"],
            }
            if expires_at >= now:
                active.append(entry)
            else:
                expired.append(entry)

        return {
            "active_locks": len(active),
            "expired_locks": len(expired),
            "locks": active,
        }

    # ---- Full snapshot ----

    def snapshot(self) -> dict[str, Any]:
        """Complete metrics snapshot combining all metrics."""
        return {
            "timestamp": time.time(),
            "queue_counts": self.queue_counts(),
            "work_latency": self.work_latency(),
            "agent_activity": self.agent_activity(),
            "budget_burn_rate": self.budget_burn_rate(),
            "info_gain_accuracy": self.info_gain_accuracy(),
            "lock_status": self.lock_status(),
        }

    # ---- Audit trail integration ----

    def emit_to_audit_log(self, log_dir: str | Path | None = None) -> None:
        """Write a metrics snapshot to the agent audit log in JSONL format.

        Compatible with agent_log.sh format: {ts, session, level, cat, msg, details}
        """
        snapshot = self.snapshot()
        log_dir = Path(log_dir) if log_dir else Path("logs")
        log_file = log_dir / "agent_audit.log"
        log_dir.mkdir(parents=True, exist_ok=True)

        entry = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "session": "metrics",
            "level": "INFO",
            "cat": "SWARM_METRICS",
            "msg": f"queue={snapshot['queue_counts']} latency_count={snapshot['work_latency']['count']}",
            "details": json.dumps(snapshot),
        }
        with open(log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")


def _percentiles(values: list[float]) -> dict[str, float]:
    """Compute p50, p95, p99, min, max, mean for a list of values."""
    if not values:
        return {}
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    return {
        "min": round(sorted_vals[0], 4),
        "p50": round(sorted_vals[n // 2], 4),
        "p95": round(sorted_vals[int(n * 0.95)], 4) if n >= 20 else round(sorted_vals[-1], 4),
        "p99": round(sorted_vals[int(n * 0.99)], 4) if n >= 100 else round(sorted_vals[-1], 4),
        "max": round(sorted_vals[-1], 4),
        "mean": round(statistics.mean(values), 4),
    }
