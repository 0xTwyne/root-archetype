# {{PROJECT_NAME}} — AI Assistant Guide

## Purpose

Umbrella repository for cross-repo coordination and governance. No application code lives here.

## Repository Map

| Repo | Path | Purpose |
|------|------|---------|
| {{PROJECT_NAME}} (this) | `{{PROJECT_ROOT}}` | Governance, agents, hooks, handoffs, progress, swarm coordination |
{{REPO_MAP_ROWS}}

## Dependency Map

See `.claude/dependency-map.json` for formal coupling edges between repos.

## Governance Infrastructure

### Hooks (`scripts/hooks/`)
Pre/post tool-use hooks for Claude Code sessions:
- Filesystem path safety (`check_filesystem_path.sh`)
- Agent schema validation (`agents_schema_guard.sh`)
- Agent reference validation (`agents_reference_guard.sh`)
- Test safety (`check_test_safety.sh`)

### Validators (`scripts/validate/`)
- Agent structure validation (`validate_agents_structure.py`)
- Reference integrity (`validate_agents_references.py`)
- CLAUDE.md matrix consistency (planned — see Issue #1)
- Document drift detection (planned — see Issue #1)

### Agent System (`agents/`)
Thin-map architecture:
- `shared/` — Cross-cutting policy (operating constraints, engineering standards, workflows)
- Role overlays — Per-agent specialization files (6-section schema)

### Swarm Coordination (`swarm/`)
SQLite-backed agent coordination with priority scheduling:
- Agent registration + heartbeat
- Work queue with information-gain-aware priority scoring
- Message board (channels + threaded posts)
- Resource locks with TTL
- Experiment scheduler

### Skills (`.claude/skills/`)
Reusable skill definitions for common workflows.

### Commands (`.claude/commands/`)
Slash command definitions for Claude Code sessions.

## Handoff Workflow

- `handoffs/active/` — In-progress work
- `handoffs/blocked/` — Waiting on dependencies
- `handoffs/completed/` — Done
- `handoffs/archived/` — Historical reference

## Progress Tracking

Daily progress in `progress/YYYY-MM/YYYY-MM-DD.md`.

## Agent Logging

```bash
source scripts/utils/agent_log.sh
agent_session_start "Session purpose"
agent_task_start "Description" "Reasoning"
agent_task_end "Description" "success|failure"
```

Audit trail in `logs/agent_audit.log`. Analysis: `scripts/utils/agent_log_analyze.sh --summary`.

## Session Management

- `scripts/session/session_init.sh` — Initialize session, verify environment
- `scripts/session/health_check.sh` — System health diagnostics

## Child Repo Management

- `scripts/repos/register-repo.sh` — Register child repo, seed agent files if missing
- `scripts/repos/scan-agents.sh` — Discover agents across all registered repos
- `scripts/repos/sync-repos.sh` — Pull all registered repos, rebuild indexes

## Code Style

- Shell: `#!/bin/bash` with `set -euo pipefail`
- Always log actions via agent_log.sh
- Run validation after producing artifacts
