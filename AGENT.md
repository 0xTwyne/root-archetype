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
- `.claude/skills/` — Skills, tracked in git (see `.claude/skills/DISCOVERY.md`)
- `.claude/commands/` — Slash commands, tracked in git

## Governance

- **Hooks**: `scripts/hooks/` — security gates, audit logging, filesystem safety, schema validation
- **Secrets**: `secrets/` — protected paths (contents gitignored, never readable by agents)
- **Logging**: `scripts/utils/agent_log.sh` — append-only audit trail
- **Validators**: `scripts/validate/` — structural integrity checks (agents, documents, skills, hooks)

## Knowledge

All project knowledge lives in the knowledge repo (`repos/<log_repo_name>/`):
the compiled wiki (`wiki/`), the taxonomy (`wiki/taxonomy.yaml`) and structured
research (`research/`). The archetype's own root `knowledge/` directory is
internal documentation about the archetype and is never copied into projects.

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

## Scratch Space

- `tmp/` — shared throwaway working space (directory tracked, contents gitignored)

Use `tmp/` for anything a session produces that should not be committed:
experiment output, intermediate data, a scratch clone of a child repo. Use
`local/notes/` instead for personal material that should persist across sessions.

Two properties matter, and both come from it being *inside the repo but ignored*:

- Ignored paths are never staged by `git add -A`, so nothing in `tmp/` can be
  swept into a session PR by the session-end hook.
- It is still readable by every other session and collaborator working from the
  root clone — unlike a directory outside the tree, which no one else can reach
  and the wrap-up survey cannot see.

Do not put working files in a sibling directory outside the root clone. Nothing
there is visible to anyone else, and `scripts/hooks/check_filesystem_path.sh`
refuses to write to it anyway. Nothing in `tmp/` is backed up or survives a clean
checkout — work meant to outlive the session belongs on a branch of the repo it
came from.

## Session Management

- `scripts/session/session_init.sh` — initialize session, verify environment
- `scripts/session/health_check.sh` — system health diagnostics

## Code Style

- Shell: `#!/bin/bash` with `set -euo pipefail`
- Log actions via `scripts/utils/agent_log.sh`
- Run validators after producing artifacts
