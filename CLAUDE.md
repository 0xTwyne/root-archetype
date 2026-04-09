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
- Skill usage logging (`skill_usage_log.sh`)

### Validators (`scripts/validate/`)
- Agent structure validation (`validate_agents_structure.py`)
- Reference integrity (`validate_agents_references.py`)
- CLAUDE.md matrix consistency (`validate_claude_md_consistency.py`)
- Document drift detection (`validate_document_drift.py`)
- Skills validation (`validate_skills.py`)

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
Reusable skill definitions for common workflows:
- Swarm coordination (`swarm/`)
- Upstream contribution (`upstream/`)
- Code simplification review (`simplify/`)
- Skill scaffolding (`new-skill/`)
- Handoff creation (`new-handoff/`)
- Safe commit with secret scanning (`safe-commit/`)
- Skill discovery (`find-skills/`)
- Project wiki maintenance (`project-wiki/`)

### Commands (`.claude/commands/`)
Slash command definitions for Claude Code sessions:
- `/swarm` — Swarm coordination operations (`swarm.md`)
- `/upstream` — Contribute instance changes back to archetype (`upstream.md`)
- `/simplify` — Review changed code for reuse, quality, and efficiency (`simplify.md`)

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

## Codebase Intelligence (GitNexus)

This project uses [GitNexus](https://github.com/abhigyanpatwari/GitNexus) for structural codebase awareness across all registered repos. GitNexus builds a knowledge graph (symbols, call edges, clusters, execution flows) from source code and exposes it via CLI tools and MCP.

### Setup

```bash
npm install -g gitnexus       # One-time global install
gitnexus analyze .             # Index this repo
scripts/repos/sync-repos.sh   # Indexes all child repos automatically
```

### Usage

Before modifying code, query the graph:

| Command | Purpose |
|---------|---------|
| `gitnexus context <symbol>` | 360-degree view: callers, callees, processes |
| `gitnexus impact <symbol>` | Blast radius: what breaks if you change this |
| `gitnexus query "<concept>"` | Find execution flows by concept |
| `gitnexus list` | Show all indexed repos |

### Cross-Repo Awareness

All registered child repos are indexed into a shared global registry (`~/.gitnexus/registry.json`). Use `--repo <name>` to target a specific repo:

```bash
gitnexus context --repo my-app validateUser
gitnexus impact --repo my-lib parseConfig
```

### Re-indexing

Indexes go stale when code changes. Re-index after significant work:

```bash
gitnexus analyze .                    # This repo only
scripts/repos/sync-repos.sh --index  # All child repos
```

## Code Style

- Shell: `#!/bin/bash` with `set -euo pipefail`
- Always log actions via agent_log.sh
- Run validation after producing artifacts
