# {{PROJECT_NAME}} — Agent Instructions

## Purpose

Umbrella repository for cross-repo coordination and governance. No application code lives here. This is the root governance repo — it defines agent roles, shared policy, hooks, and knowledge management for all child repos.

## Repository Map

| Repo | Path | Purpose |
|------|------|---------|
| {{PROJECT_NAME}} (this) | `{{PROJECT_ROOT}}` | Governance, agents, hooks, notes, knowledge |
{{REPO_MAP_ROWS}}

## Agent System

- `agents/shared/` — Cross-cutting policy inherited by all roles (operating constraints, engineering standards, workflows)
- `agents/roles/` — Role-specific overlays (6-section schema: Mission, Use This Role When, Inputs Required, Outputs, Workflow, Guardrails)
- `agents/skills/` — Reusable methodology and skill definitions (see `agents/skills/DISCOVERY.md`)
- `.claude/commands/` — Engine-specific slash commands (generated at init from `agents/engines/`)

## Governance

- **Hooks**: `scripts/hooks/` — security gates, audit logging, filesystem safety, schema validation
- **Secrets**: `secrets/` — protected paths (contents gitignored, never readable by agents)
- **Logging**: `scripts/utils/agent_log.sh` — append-only audit trail
- **Validators**: `scripts/validate/` — structural integrity checks (agents, documents, skills, hooks)

## Knowledge

- `knowledge/wiki/` — compiled master wiki (maintained by project maintainers)
- `knowledge/research/` — structured research and deep dives

### Log Repo (registered in `repos/`)

Session logs, notes, handoffs, and per-member wiki compilations live in a
separate log repo. Resolve from `.archetype-manifest.json` → `log_repo_name`.

- `<log-repo>/logs/progress/<user>/` — per-user session progress logs
- `<log-repo>/notes/<user>/` — per-user notes, plans, handoffs
- `<log-repo>/wiki/<user>/` — per-member wiki compilations

## Child Repos

- `scripts/repos/register-repo.sh` — register a child repo (creates symlink in `repos/`)
- `scripts/repos/scan-agents.sh` — discover agents across all registered repos
- `scripts/repos/sync-repos.sh` — pull and sync all registered repos
- Child repos are self-contained (own `AGENT.md`); root adds cross-repo context

## Local Customization

- `local/skills/` — personal skills (gitignored)
- `local/hooks/` — personal hooks (gitignored)
- `local/notes/` — personal scratchpad (gitignored)

## Session Management

- `scripts/session/session_init.sh` — initialize session, verify environment
- `scripts/session/health_check.sh` — system health diagnostics

## Code Style

- Shell: `#!/bin/bash` with `set -euo pipefail`
- Log actions via `scripts/utils/agent_log.sh`
- Run validators after producing artifacts
