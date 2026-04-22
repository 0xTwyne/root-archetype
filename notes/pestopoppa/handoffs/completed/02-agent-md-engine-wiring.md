# Handoff 2: AGENT.md + Engine Wiring

**Status**: completed
**Created**: 2026-04-09
**Priority**: 2 (depends on Handoff 1 completing structure cleanup)
**Estimated scope**: 4 new files, 2 rewrites, skill migration

---

## Context

The repo currently uses `CLAUDE.md` as the primary instruction file — tightly coupling the template to a single AI engine. This handoff creates `AGENT.md` as the engine-neutral canonical file and rewrites `CLAUDE.md` as a thin pointer. It also creates `CODEX.md` to demonstrate the engine-neutral pattern.

---

## Prerequisites

- Handoff 1 complete (directory structure clean, agents/roles/ in place)

---

## Tasks

### A. Write `AGENT.md` (~100 lines)

This is the NEW primary file. It replaces CLAUDE.md as the source of truth. Contents:

```markdown
# {{PROJECT_NAME}} — Agent Instructions

## Purpose
[1-2 sentences: what this project does, that it's a governance root repo]

## Repository Map
| Repo | Path | Purpose |
[root + child repos table with {{TEMPLATE}} placeholders]

## Agent System
- `agents/shared/` — Cross-cutting policy inherited by all roles
- `agents/roles/` — Role-specific overlays (6-section schema)
- `agents/skills/` — Reusable methodology (see agents/skills/DISCOVERY.md)

## Governance
- Hooks: `scripts/hooks/` — security, audit, filesystem safety
- Secrets: `secrets/` — protected paths (never readable by agents)
- Logging: `scripts/utils/agent_log.sh` — audit trail
- Validators: `scripts/validate/` — structural integrity checks

## Knowledge
- `knowledge/wiki/` — compiled shared knowledge
- `knowledge/research/` — structured research intake
- `notes/<user>/` — per-user notes, plans, handoffs
- `logs/progress/<user>/` — per-user session progress

## Child Repos
- `scripts/repos/register-repo.sh` — register a child repo
- `scripts/repos/scan-agents.sh` — discover agents across repos
- Child repos are self-contained (own AGENT.md); root adds cross-repo context

## Local Customization
- `local/skills/` — personal skills (gitignored)
- `local/hooks/` — personal hooks (gitignored)
- `local/notes/` — personal scratchpad (gitignored)

## Code Style
- Shell: `#!/bin/bash` with `set -euo pipefail`
- Log actions via agent_log.sh
- Run validators after producing artifacts
```

Key design points:
- No engine-specific language (no "Claude", "Codex", etc.)
- Template placeholders use `{{DOUBLE_BRACES}}`
- References directory paths, not tool-specific discovery mechanisms
- ~100 lines — concise, scannable

### B. Rewrite `CLAUDE.md` (~25 lines)

Strip to a thin pointer:

```markdown
# Claude Code Configuration

> Primary instructions: read `AGENT.md` in this directory.
> This file contains Claude Code-specific wiring only.

## Engine Wiring

- Settings: `.claude/settings.json` — hook paths, permissions
- Skills: `.claude/skills/` — thin wrappers referencing `agents/skills/`
- Local overrides: `.claude/settings.local.json` (gitignored)

## Skill Discovery

Claude Code discovers skills via `.claude/skills/{name}/SKILL.md`.
Engine-neutral skill content lives in `agents/skills/{name}/SKILL.md`.
Claude wrappers include the engine-neutral content via reference.

## Hooks

All hooks live in `scripts/hooks/`. Claude wiring in `.claude/settings.json`
points to those paths. See `scripts/hooks/README.md` for the full list.
```

### C. Write `CODEX.md` (~20 lines)

```markdown
# Codex Configuration

> Primary instructions: read `AGENT.md` in this directory.
> This file contains Codex/OpenAI-specific wiring only.

## Engine Wiring

- Skills: read directly from `agents/skills/` (no wrapper layer needed)
- Agent roles: `agents/roles/*.md`
- Shared policy: `agents/shared/*.md`

## Hooks

Codex does not currently support hook wiring. Safety hooks in `scripts/hooks/`
can be integrated via CI/CD or pre-commit hooks.
```

### D. Create `MAINTAINERS.json` in project root

Move from `.claude/maintainers.json` → root `MAINTAINERS.json`. Update format:

```json
{
  "project": "{{PROJECT_NAME}}",
  "global_maintainers": ["{{MAINTAINER_EMAIL}}"],
  "repo_maintainers": {}
}
```

Delete `.claude/maintainers.json` after migration.

### E. Migrate skills to `agents/skills/`

For each skill that survives Handoff 1 (simplify, safe-commit, new-skill, new-handoff, project-wiki):

1. Move `SKILL.md` + supporting files from `.claude/skills/{name}/` → `agents/skills/{name}/`
2. Create thin `.claude/skills/{name}/SKILL.md` wrapper that references the engine-neutral version:

```markdown
---
name: {skill-name}
description: {description}
---

<!-- Engine wrapper: Claude Code skill discovery -->
<!-- Full methodology: agents/skills/{name}/SKILL.md -->

Read and follow the instructions in `agents/skills/{name}/SKILL.md`.
```

3. Move any `scripts/`, `references/`, `assets/` subdirectories with the skill

### F. Write `agents/skills/DISCOVERY.md`

Catalog of all available skills with trigger conditions:

```markdown
# Skill Discovery

| Skill | Path | Trigger | Description |
|-------|------|---------|-------------|
| simplify | agents/skills/simplify/ | /simplify or code review | Review changed code for reuse and quality |
| safe-commit | agents/skills/safe-commit/ | /commit or committing | Secret-scanning commit workflow |
| new-skill | agents/skills/new-skill/ | Creating a new skill | Skill scaffolding methodology |
| new-handoff | agents/skills/new-handoff/ | Creating a handoff | Handoff document template |
| project-wiki | agents/skills/project-wiki/ | /project-wiki | Wiki compilation and maintenance |
| research-intake | agents/skills/research-intake/ | /research-intake | Structured research ingestion |
| init-wizard | agents/skills/init-wizard/ | .needs-init detected | Guided project initialization |

## Engine-Specific Discovery

- **Claude Code**: `.claude/skills/{name}/SKILL.md` thin wrappers
- **Codex**: Read `agents/skills/` directly
- **Other**: Read this file for the catalog
```

---

## Acceptance Criteria

1. `AGENT.md` exists at project root, is engine-neutral, ~100 lines
2. `CLAUDE.md` is ≤30 lines, references `AGENT.md`
3. `CODEX.md` exists, references `AGENT.md`
4. `MAINTAINERS.json` at root, `.claude/maintainers.json` deleted
5. All surviving skills have content in `agents/skills/` and thin wrappers in `.claude/skills/`
6. `agents/skills/DISCOVERY.md` exists with complete catalog
7. No engine-specific language in `AGENT.md` (grep for "Claude", "Codex", "Anthropic" — should be 0 hits)

---

## Risks

- **Skill wrapper format**: Claude Code skill discovery relies on YAML frontmatter + SKILL.md path. Test that thin wrappers with a `Read` reference actually work (Claude may need the full content inlined vs. referenced).
- **CLAUDE.md expectations**: Some Claude Code features may auto-read CLAUDE.md. Ensure the thin pointer still provides enough context for effective sessions. If not, inline the critical sections from AGENT.md.
