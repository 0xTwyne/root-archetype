# Swarm Coordination Primitive

SQLite-backed multi-agent coordination for governed, single-machine environments.

Inspired by [agenthub](https://github.com/karpathy/agenthub) but adapted for:
- Governed environments (hooks, validators, schema enforcement)
- Single-machine operation (shared filesystem, not HTTP)
- Inference-bottlenecked workflows (priority scheduling, not FIFO)

## Architecture

```
┌─────────────────────────────────────────┐
│           Coordinator (SQLite)           │
│  ┌──────────┐ ┌────────┐ ┌───────────┐ │
│  │ Work Queue│ │Messages│ │  Locks    │ │
│  │ (priority)│ │(board) │ │  (TTL)   │ │
│  └──────────┘ └────────┘ └───────────┘ │
│  ┌──────────┐ ┌────────┐ ┌───────────┐ │
│  │  Agents  │ │ Budget │ │ Scheduler │ │
│  │(registry)│ │(ledger)│ │   (EI)    │ │
│  └──────────┘ └────────┘ └───────────┘ │
└─────────────────────────────────────────┘
         ▲           ▲           ▲
         │           │           │
    ┌────┴────┐ ┌────┴────┐ ┌───┴─────┐
    │ Worker 1│ │ Worker 2│ │ Worker N│
    │(worktree)│(worktree)│ │(worktree)│
    └─────────┘ └─────────┘ └─────────┘
```

## Components

### Coordinator (`coordinator.py`)
- Agent registration + heartbeat + stale-claim release
- Work queue with priority scoring
- Message board (channels + threaded posts)
- Resource locks with TTL
- Budget enforcement per agent

### Experiment Scheduler (`scheduler.py`)
- Expected Improvement over Pareto hypervolume
- Re-scores all pending experiments after each validation
- Species diversity tracking
- Config novelty computation

### Swarm Client (`client.py`)
- Thin library for agents to interact with coordinator
- Context manager support (auto-start/stop heartbeat)
- Lock tracking and cleanup on exit

### Metrics (`metrics.py`)
- Read-only metrics exporter for coordinator database
- Work item latency distributions (p50/p95/p99)
- Budget burn-rate per agent with action type breakdown
- Agent activity tracking and information gain accuracy
- Audit trail integration via `emit_to_audit_log()`

## Usage

```python
from swarm import Coordinator, SwarmClient, ExperimentScheduler

# Create coordinator (shared by all agents)
coord = Coordinator("swarm/coordinator.db")

# Create experiment scheduler
scheduler = ExperimentScheduler(coord, objective_names=["quality", "speed"])

# Agent usage
with SwarmClient(coord, name="worker-1", role="explorer") as client:
    # Submit experiment
    item_id = client.submit_experiment(
        title="Parameter sweep batch A",
        description="Test config variant A3 against baseline",
        predicted_info_value=0.7,
        predicted_objectives={"quality": 2.5, "speed": 30.0},
        config={"variant": "A3", "batch_size": 64},
        species="explorer",
    )

    # Claim and execute work
    work = client.claim_work()
    if work:
        # ... do work ...
        client.complete_work(work.item_id, result="success")

    # Use message board
    msg_id = client.post("findings", "Variant A3 shows 2.5 quality at 30 ops/s")
    messages = client.read_messages("findings")

    # Acquire resource lock
    if client.acquire_lock("compute_endpoint", ttl_seconds=300):
        try:
            # ... use shared compute resource ...
            pass
        finally:
            client.release_lock("compute_endpoint")
```

## Two-Speed System

The swarm addresses the resource bottleneck when a shared compute resource (GPU endpoint, evaluation service, etc.) is scarce:

- **Fast lane**: Workers design experiments, analyze results, propose mutations in parallel (no shared resource needed)
- **Slow lane**: Validation requires sequential access to the shared resource — one experiment at a time

The scheduler maximizes **Pareto frontier information per unit of shared resource time**.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| SQLite-first (no HTTP) | Shared filesystem; <10 agents; WAL mode handles concurrency |
| Priority queue (not FIFO) | Information-gain-aware scheduling maximizes resource utility |
| Worktree isolation | Each agent gets isolated code copy; governance hooks apply per-worktree |
| Dumb coordinator, smart agents | Coordinator stores data; agents make decisions (agenthub philosophy) |
| Budget enforcement | Prevents runaway agents; MetaOptimizer adjusts budgets based on effectiveness |
