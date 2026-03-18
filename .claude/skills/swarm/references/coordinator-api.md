# Swarm Coordinator API Reference

## Database

SQLite with WAL mode at `swarm/coordinator.db`. Created automatically on first `Coordinator()` init.

## Tables

### agents
| Column | Type | Notes |
|--------|------|-------|
| agent_id | TEXT PK | UUID |
| name | TEXT | Human-readable name |
| role | TEXT | Agent role (e.g. "developer", "reviewer") |
| registered_at | REAL | Unix timestamp |
| last_heartbeat | REAL | Unix timestamp, stale after `HEARTBEAT_STALE_SECONDS` |
| budget_remaining | REAL | Default 100.0 |
| metadata | TEXT | JSON blob |

### work_items
| Column | Type | Notes |
|--------|------|-------|
| item_id | TEXT PK | UUID |
| title | TEXT | Short description |
| description | TEXT | Full description |
| priority | REAL | Higher = more important. Indexed DESC with status |
| status | TEXT | `pending`, `claimed`, `completed`, `failed`, `withdrawn` |
| created_by | TEXT FK→agents | |
| claimed_by | TEXT FK→agents | NULL until claimed |
| created_at | REAL | Unix timestamp |
| claimed_at | REAL | NULL until claimed |
| completed_at | REAL | NULL until completed |
| result | TEXT | Output of work |
| metadata | TEXT | JSON blob |
| predicted_info_value | REAL | Scheduler prediction |
| actual_info_gain | REAL | Measured after completion |
| parent_item_id | TEXT FK→work_items | For hierarchical tasks |

### messages
| Column | Type | Notes |
|--------|------|-------|
| message_id | TEXT PK | UUID |
| channel | TEXT | Channel name, indexed with posted_at |
| author | TEXT FK→agents | |
| content | TEXT | Message body |
| posted_at | REAL | Unix timestamp |
| thread_id | TEXT | NULL for top-level, parent message_id for replies |
| metadata | TEXT | JSON blob |

### resource_locks
| Column | Type | Notes |
|--------|------|-------|
| resource_id | TEXT PK | Resource being locked |
| holder | TEXT FK→agents | Agent holding lock |
| acquired_at | REAL | Unix timestamp |
| ttl_seconds | REAL | Lock expires after this many seconds |
| metadata | TEXT | JSON blob |

## Python API

```python
from swarm import Coordinator, SwarmClient

# Direct coordinator usage
coord = Coordinator("swarm/coordinator.db")
coord.register_agent(name="worker-1", role="developer")
coord.submit_work(title="Fix bug", description="...", priority=5.0, created_by=agent_id)
coord.release_lock(resource_id)

# Client wrapper (recommended)
with SwarmClient(coord, name="worker-1", role="developer") as client:
    work = client.claim_work()       # Claims highest-priority pending item
    client.post_message("general", "Starting work on ...")
    client.complete_work(work.item_id, result="Fixed in commit abc123")
```

## Key constants (from `swarm/constants.py`)

| Constant | Purpose |
|----------|---------|
| `HEARTBEAT_STALE_SECONDS` | Agent considered dead after this many seconds without heartbeat |
| `DEFAULT_LOCK_TTL` | Default TTL for resource locks |
| `DEFAULT_AGENT_BUDGET` | Starting budget for new agents |
