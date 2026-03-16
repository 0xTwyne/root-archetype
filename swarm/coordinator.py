"""
Swarm Coordinator — SQLite-backed agent coordination.

Provides:
- Agent registration + heartbeat + stale-claim release
- Work queue with priority scoring (not FIFO)
- Message board (channels + threaded posts)
- Resource locks with TTL
- Budget enforcement per agent
"""

import json
import sqlite3
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path
from typing import Any, Optional

from swarm.constants import (
    SQLITE_CONNECT_TIMEOUT,
    SQLITE_BUSY_TIMEOUT,
    HEARTBEAT_STALE_SECONDS as _HEARTBEAT_STALE_SECONDS,
    DEFAULT_LOCK_TTL as _DEFAULT_LOCK_TTL,
    DEFAULT_AGENT_BUDGET,
    DEFAULT_WORK_LIST_LIMIT,
    DEFAULT_MESSAGE_LIMIT,
    DEFAULT_BUDGET_HISTORY_LIMIT,
)


class WorkItemStatus(str, Enum):
    PENDING = "pending"
    CLAIMED = "claimed"
    COMPLETED = "completed"
    FAILED = "failed"
    WITHDRAWN = "withdrawn"


@dataclass
class Agent:
    agent_id: str
    name: str
    role: str
    registered_at: float
    last_heartbeat: float
    budget_remaining: float = 100.0
    metadata: dict = field(default_factory=dict)


@dataclass
class WorkItem:
    item_id: str
    title: str
    description: str
    priority: float  # Higher = more important
    status: WorkItemStatus
    created_by: str
    claimed_by: Optional[str] = None
    created_at: float = 0.0
    claimed_at: Optional[float] = None
    completed_at: Optional[float] = None
    result: Optional[str] = None
    metadata: dict = field(default_factory=dict)
    # Experiment-specific fields
    predicted_info_value: float = 0.0
    actual_info_gain: Optional[float] = None
    parent_item_id: Optional[str] = None


@dataclass
class Message:
    message_id: str
    channel: str
    author: str
    content: str
    posted_at: float
    thread_id: Optional[str] = None
    metadata: dict = field(default_factory=dict)


@dataclass
class ResourceLock:
    resource_id: str
    holder: str
    acquired_at: float
    ttl_seconds: float
    metadata: dict = field(default_factory=dict)


class Coordinator:
    """SQLite-backed swarm coordinator.

    Thread-safe via SQLite WAL mode. Designed for shared-filesystem access
    by multiple agents (no HTTP server needed for <10 agents).
    """

    HEARTBEAT_STALE_SECONDS = _HEARTBEAT_STALE_SECONDS
    DEFAULT_LOCK_TTL = _DEFAULT_LOCK_TTL

    def __init__(self, db_path: str | Path = "swarm/coordinator.db"):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    @contextmanager
    def _conn(self):
        """Context manager for database connections with WAL mode."""
        conn = sqlite3.connect(
            str(self.db_path),
            timeout=SQLITE_CONNECT_TIMEOUT,
            isolation_level=None,  # autocommit for WAL
        )
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT}")
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def _init_db(self):
        """Create tables if they don't exist."""
        with self._conn() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS agents (
                    agent_id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    role TEXT NOT NULL,
                    registered_at REAL NOT NULL,
                    last_heartbeat REAL NOT NULL,
                    budget_remaining REAL DEFAULT 100.0,
                    metadata TEXT DEFAULT '{}'
                );

                CREATE TABLE IF NOT EXISTS work_items (
                    item_id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    description TEXT DEFAULT '',
                    priority REAL DEFAULT 0.0,
                    status TEXT DEFAULT 'pending',
                    created_by TEXT NOT NULL,
                    claimed_by TEXT,
                    created_at REAL NOT NULL,
                    claimed_at REAL,
                    completed_at REAL,
                    result TEXT,
                    metadata TEXT DEFAULT '{}',
                    predicted_info_value REAL DEFAULT 0.0,
                    actual_info_gain REAL,
                    parent_item_id TEXT,
                    FOREIGN KEY (created_by) REFERENCES agents(agent_id),
                    FOREIGN KEY (claimed_by) REFERENCES agents(agent_id),
                    FOREIGN KEY (parent_item_id) REFERENCES work_items(item_id)
                );

                CREATE INDEX IF NOT EXISTS idx_work_status_priority
                    ON work_items(status, priority DESC);

                CREATE TABLE IF NOT EXISTS messages (
                    message_id TEXT PRIMARY KEY,
                    channel TEXT NOT NULL,
                    author TEXT NOT NULL,
                    content TEXT NOT NULL,
                    posted_at REAL NOT NULL,
                    thread_id TEXT,
                    metadata TEXT DEFAULT '{}',
                    FOREIGN KEY (author) REFERENCES agents(agent_id)
                );

                CREATE INDEX IF NOT EXISTS idx_messages_channel
                    ON messages(channel, posted_at);

                CREATE INDEX IF NOT EXISTS idx_messages_thread
                    ON messages(thread_id, posted_at);

                CREATE TABLE IF NOT EXISTS resource_locks (
                    resource_id TEXT PRIMARY KEY,
                    holder TEXT NOT NULL,
                    acquired_at REAL NOT NULL,
                    ttl_seconds REAL NOT NULL,
                    metadata TEXT DEFAULT '{}',
                    FOREIGN KEY (holder) REFERENCES agents(agent_id)
                );

                CREATE TABLE IF NOT EXISTS budget_ledger (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    agent_id TEXT NOT NULL,
                    action_type TEXT NOT NULL,
                    cost REAL NOT NULL,
                    timestamp REAL NOT NULL,
                    description TEXT DEFAULT '',
                    FOREIGN KEY (agent_id) REFERENCES agents(agent_id)
                );
            """)

    # ---- Agent Management ----

    def register_agent(
        self, name: str, role: str, budget: float = DEFAULT_AGENT_BUDGET, metadata: dict | None = None
    ) -> str:
        """Register a new agent. Returns agent_id."""
        agent_id = f"agent_{uuid.uuid4().hex[:12]}"
        now = time.time()
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO agents (agent_id, name, role, registered_at, last_heartbeat, budget_remaining, metadata) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (agent_id, name, role, now, now, budget, json.dumps(metadata or {})),
            )
        return agent_id

    def heartbeat(self, agent_id: str) -> bool:
        """Update agent heartbeat. Returns False if agent not found."""
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE agents SET last_heartbeat = ? WHERE agent_id = ?",
                (time.time(), agent_id),
            )
            return cursor.rowcount > 0

    def get_agent(self, agent_id: str) -> Agent | None:
        """Get agent by ID."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT * FROM agents WHERE agent_id = ?", (agent_id,)
            ).fetchone()
            if row:
                return Agent(
                    agent_id=row["agent_id"],
                    name=row["name"],
                    role=row["role"],
                    registered_at=row["registered_at"],
                    last_heartbeat=row["last_heartbeat"],
                    budget_remaining=row["budget_remaining"],
                    metadata=json.loads(row["metadata"]),
                )
        return None

    def list_agents(self, active_only: bool = True) -> list[Agent]:
        """List all registered agents. If active_only, exclude stale agents."""
        cutoff = time.time() - self.HEARTBEAT_STALE_SECONDS if active_only else 0
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT * FROM agents WHERE last_heartbeat >= ? ORDER BY name",
                (cutoff,),
            ).fetchall()
            return [
                Agent(
                    agent_id=r["agent_id"],
                    name=r["name"],
                    role=r["role"],
                    registered_at=r["registered_at"],
                    last_heartbeat=r["last_heartbeat"],
                    budget_remaining=r["budget_remaining"],
                    metadata=json.loads(r["metadata"]),
                )
                for r in rows
            ]

    def release_stale_claims(self) -> int:
        """Release work items claimed by stale agents. Returns count released."""
        cutoff = time.time() - self.HEARTBEAT_STALE_SECONDS
        with self._conn() as conn:
            # Find stale agents
            stale = conn.execute(
                "SELECT agent_id FROM agents WHERE last_heartbeat < ?", (cutoff,)
            ).fetchall()
            stale_ids = [r["agent_id"] for r in stale]
            if not stale_ids:
                return 0
            placeholders = ",".join("?" * len(stale_ids))
            cursor = conn.execute(
                f"UPDATE work_items SET status = 'pending', claimed_by = NULL, claimed_at = NULL "
                f"WHERE status = 'claimed' AND claimed_by IN ({placeholders})",
                stale_ids,
            )
            # Also release their locks
            conn.execute(
                f"DELETE FROM resource_locks WHERE holder IN ({placeholders})",
                stale_ids,
            )
            return cursor.rowcount

    # ---- Work Queue ----

    def submit_work(
        self,
        title: str,
        description: str,
        created_by: str,
        priority: float = 0.0,
        predicted_info_value: float = 0.0,
        parent_item_id: str | None = None,
        metadata: dict | None = None,
    ) -> str:
        """Submit a work item to the queue. Returns item_id."""
        item_id = f"wi_{uuid.uuid4().hex[:12]}"
        now = time.time()
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO work_items "
                "(item_id, title, description, priority, status, created_by, created_at, "
                "predicted_info_value, parent_item_id, metadata) "
                "VALUES (?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)",
                (
                    item_id, title, description, priority, created_by, now,
                    predicted_info_value, parent_item_id,
                    json.dumps(metadata or {}),
                ),
            )
        return item_id

    def claim_work(self, agent_id: str) -> WorkItem | None:
        """Claim the highest-priority pending work item. Returns None if queue empty."""
        now = time.time()
        with self._conn() as conn:
            # Atomic claim: select + update in one transaction
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = conn.execute(
                    "SELECT * FROM work_items WHERE status = 'pending' "
                    "ORDER BY priority DESC, created_at ASC LIMIT 1"
                ).fetchone()
                if not row:
                    conn.execute("ROLLBACK")
                    return None
                conn.execute(
                    "UPDATE work_items SET status = 'claimed', claimed_by = ?, claimed_at = ? "
                    "WHERE item_id = ? AND status = 'pending'",
                    (agent_id, now, row["item_id"]),
                )
                conn.execute("COMMIT")
                return WorkItem(
                    item_id=row["item_id"],
                    title=row["title"],
                    description=row["description"],
                    priority=row["priority"],
                    status=WorkItemStatus.CLAIMED,
                    created_by=row["created_by"],
                    claimed_by=agent_id,
                    created_at=row["created_at"],
                    claimed_at=now,
                    metadata=json.loads(row["metadata"]),
                    predicted_info_value=row["predicted_info_value"],
                    parent_item_id=row["parent_item_id"],
                )
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def complete_work(
        self, item_id: str, agent_id: str, result: str = "",
        actual_info_gain: float | None = None,
    ) -> bool:
        """Mark a work item as completed. Returns False if not claimed by agent."""
        now = time.time()
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE work_items SET status = 'completed', completed_at = ?, result = ?, "
                "actual_info_gain = ? "
                "WHERE item_id = ? AND claimed_by = ? AND status = 'claimed'",
                (now, result, actual_info_gain, item_id, agent_id),
            )
            return cursor.rowcount > 0

    def fail_work(self, item_id: str, agent_id: str, result: str = "") -> bool:
        """Mark a work item as failed."""
        now = time.time()
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE work_items SET status = 'failed', completed_at = ?, result = ? "
                "WHERE item_id = ? AND claimed_by = ? AND status = 'claimed'",
                (now, result, item_id, agent_id),
            )
            return cursor.rowcount > 0

    def withdraw_work(self, item_id: str, agent_id: str) -> bool:
        """Withdraw a pending work item submitted by this agent."""
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE work_items SET status = 'withdrawn' "
                "WHERE item_id = ? AND created_by = ? AND status = 'pending'",
                (item_id, agent_id),
            )
            return cursor.rowcount > 0

    def update_priority(self, item_id: str, new_priority: float) -> bool:
        """Update priority of a pending work item."""
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE work_items SET priority = ? WHERE item_id = ? AND status = 'pending'",
                (new_priority, item_id),
            )
            return cursor.rowcount > 0

    def list_work(
        self, status: WorkItemStatus | None = None, limit: int = DEFAULT_WORK_LIST_LIMIT
    ) -> list[WorkItem]:
        """List work items, optionally filtered by status."""
        with self._conn() as conn:
            if status:
                rows = conn.execute(
                    "SELECT * FROM work_items WHERE status = ? ORDER BY priority DESC, created_at ASC LIMIT ?",
                    (status.value, limit),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM work_items ORDER BY priority DESC, created_at ASC LIMIT ?",
                    (limit,),
                ).fetchall()
            return [self._row_to_work_item(r) for r in rows]

    def get_work_item(self, item_id: str) -> WorkItem | None:
        """Get a specific work item."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT * FROM work_items WHERE item_id = ?", (item_id,)
            ).fetchone()
            return self._row_to_work_item(row) if row else None

    def pending_count(self) -> int:
        """Count pending work items."""
        with self._conn() as conn:
            row = conn.execute(
                "SELECT COUNT(*) as cnt FROM work_items WHERE status = 'pending'"
            ).fetchone()
            return row["cnt"]

    def _row_to_work_item(self, row: sqlite3.Row) -> WorkItem:
        return WorkItem(
            item_id=row["item_id"],
            title=row["title"],
            description=row["description"],
            priority=row["priority"],
            status=WorkItemStatus(row["status"]),
            created_by=row["created_by"],
            claimed_by=row["claimed_by"],
            created_at=row["created_at"],
            claimed_at=row["claimed_at"],
            completed_at=row["completed_at"],
            result=row["result"],
            metadata=json.loads(row["metadata"]),
            predicted_info_value=row["predicted_info_value"],
            actual_info_gain=row["actual_info_gain"],
            parent_item_id=row["parent_item_id"],
        )

    # ---- Message Board ----

    def post_message(
        self, channel: str, author: str, content: str,
        thread_id: str | None = None, metadata: dict | None = None,
    ) -> str:
        """Post a message to a channel. Returns message_id."""
        message_id = f"msg_{uuid.uuid4().hex[:12]}"
        now = time.time()
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO messages (message_id, channel, author, content, posted_at, thread_id, metadata) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (message_id, channel, author, content, now, thread_id, json.dumps(metadata or {})),
            )
        return message_id

    def get_messages(
        self, channel: str, since: float = 0, limit: int = DEFAULT_MESSAGE_LIMIT
    ) -> list[Message]:
        """Get messages from a channel since a timestamp."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT * FROM messages WHERE channel = ? AND posted_at > ? "
                "ORDER BY posted_at ASC LIMIT ?",
                (channel, since, limit),
            ).fetchall()
            return [
                Message(
                    message_id=r["message_id"],
                    channel=r["channel"],
                    author=r["author"],
                    content=r["content"],
                    posted_at=r["posted_at"],
                    thread_id=r["thread_id"],
                    metadata=json.loads(r["metadata"]),
                )
                for r in rows
            ]

    def get_thread(self, thread_id: str) -> list[Message]:
        """Get all messages in a thread."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT * FROM messages WHERE thread_id = ? OR message_id = ? "
                "ORDER BY posted_at ASC",
                (thread_id, thread_id),
            ).fetchall()
            return [
                Message(
                    message_id=r["message_id"],
                    channel=r["channel"],
                    author=r["author"],
                    content=r["content"],
                    posted_at=r["posted_at"],
                    thread_id=r["thread_id"],
                    metadata=json.loads(r["metadata"]),
                )
                for r in rows
            ]

    def list_channels(self) -> list[dict[str, Any]]:
        """List all channels with message counts."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT channel, COUNT(*) as count, MAX(posted_at) as last_activity "
                "FROM messages GROUP BY channel ORDER BY last_activity DESC"
            ).fetchall()
            return [{"channel": r["channel"], "count": r["count"], "last_activity": r["last_activity"]} for r in rows]

    # ---- Resource Locks ----

    def acquire_lock(
        self, resource_id: str, holder: str,
        ttl_seconds: float | None = None, metadata: dict | None = None,
    ) -> bool:
        """Try to acquire a resource lock. Returns True if acquired."""
        ttl = ttl_seconds or self.DEFAULT_LOCK_TTL
        now = time.time()
        with self._conn() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                # Clean expired locks first
                conn.execute(
                    "DELETE FROM resource_locks WHERE acquired_at + ttl_seconds < ?",
                    (now,),
                )
                # Try to insert (fails if already held)
                conn.execute(
                    "INSERT INTO resource_locks (resource_id, holder, acquired_at, ttl_seconds, metadata) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (resource_id, holder, now, ttl, json.dumps(metadata or {})),
                )
                conn.execute("COMMIT")
                return True
            except sqlite3.IntegrityError:
                conn.execute("ROLLBACK")
                return False
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def release_lock(self, resource_id: str, holder: str) -> bool:
        """Release a resource lock. Only the holder can release."""
        with self._conn() as conn:
            cursor = conn.execute(
                "DELETE FROM resource_locks WHERE resource_id = ? AND holder = ?",
                (resource_id, holder),
            )
            return cursor.rowcount > 0

    def check_lock(self, resource_id: str) -> ResourceLock | None:
        """Check if a resource is locked."""
        now = time.time()
        with self._conn() as conn:
            row = conn.execute(
                "SELECT * FROM resource_locks WHERE resource_id = ? AND acquired_at + ttl_seconds >= ?",
                (resource_id, now),
            ).fetchone()
            if row:
                return ResourceLock(
                    resource_id=row["resource_id"],
                    holder=row["holder"],
                    acquired_at=row["acquired_at"],
                    ttl_seconds=row["ttl_seconds"],
                    metadata=json.loads(row["metadata"]),
                )
        return None

    # ---- Budget Enforcement ----

    def charge_budget(
        self, agent_id: str, action_type: str, cost: float, description: str = ""
    ) -> bool:
        """Charge an agent's budget. Returns False if insufficient."""
        with self._conn() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                row = conn.execute(
                    "SELECT budget_remaining FROM agents WHERE agent_id = ?",
                    (agent_id,),
                ).fetchone()
                if not row or row["budget_remaining"] < cost:
                    conn.execute("ROLLBACK")
                    return False
                conn.execute(
                    "UPDATE agents SET budget_remaining = budget_remaining - ? WHERE agent_id = ?",
                    (cost, agent_id),
                )
                conn.execute(
                    "INSERT INTO budget_ledger (agent_id, action_type, cost, timestamp, description) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (agent_id, action_type, cost, time.time(), description),
                )
                conn.execute("COMMIT")
                return True
            except Exception:
                conn.execute("ROLLBACK")
                raise

    def get_budget_history(
        self, agent_id: str, limit: int = DEFAULT_BUDGET_HISTORY_LIMIT
    ) -> list[dict[str, Any]]:
        """Get budget ledger entries for an agent."""
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT action_type, cost, timestamp, description "
                "FROM budget_ledger WHERE agent_id = ? ORDER BY timestamp DESC LIMIT ?",
                (agent_id, limit),
            ).fetchall()
            return [
                {
                    "action_type": r["action_type"],
                    "cost": r["cost"],
                    "timestamp": r["timestamp"],
                    "description": r["description"],
                }
                for r in rows
            ]

    def set_budget(self, agent_id: str, budget: float) -> bool:
        """Set an agent's budget (for MetaOptimizer adjustments)."""
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE agents SET budget_remaining = ? WHERE agent_id = ?",
                (budget, agent_id),
            )
            return cursor.rowcount > 0

    # ---- Utilities ----

    def stats(self) -> dict[str, Any]:
        """Get coordinator statistics."""
        with self._conn() as conn:
            agents = conn.execute("SELECT COUNT(*) as cnt FROM agents").fetchone()["cnt"]
            active = len(self.list_agents(active_only=True))
            pending = conn.execute(
                "SELECT COUNT(*) as cnt FROM work_items WHERE status = 'pending'"
            ).fetchone()["cnt"]
            claimed = conn.execute(
                "SELECT COUNT(*) as cnt FROM work_items WHERE status = 'claimed'"
            ).fetchone()["cnt"]
            completed = conn.execute(
                "SELECT COUNT(*) as cnt FROM work_items WHERE status = 'completed'"
            ).fetchone()["cnt"]
            messages = conn.execute("SELECT COUNT(*) as cnt FROM messages").fetchone()["cnt"]
            locks = conn.execute("SELECT COUNT(*) as cnt FROM resource_locks").fetchone()["cnt"]
            return {
                "agents_total": agents,
                "agents_active": active,
                "work_pending": pending,
                "work_claimed": claimed,
                "work_completed": completed,
                "messages": messages,
                "locks_held": locks,
            }

    def reset(self):
        """Reset all coordinator state. DESTRUCTIVE — use with caution."""
        with self._conn() as conn:
            conn.executescript("""
                DELETE FROM budget_ledger;
                DELETE FROM resource_locks;
                DELETE FROM messages;
                DELETE FROM work_items;
                DELETE FROM agents;
            """)
