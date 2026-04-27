# Project Initialization & Setup

**Category**: tooling

`init-project.sh` quick / guided modes, the `init-wizard` skill, and what each step does.

## Summary

`init-project.sh` scaffolds a new project from root-archetype with two modes: **quick** (default, <5s) and **guided** (`--guided`, interactive). Quick mode copies template files, substitutes `{{PROJECT_NAME}}` and `{{PROJECT_ROOT}}`, and initializes git. Guided mode does the same plus drops a `.needs-init` JSON marker with 6 remaining setup steps; the next agent session detects this marker (via `session-start.sh`) and triggers the `init-wizard` skill.

The `init-wizard` skill walks the user through six interactive steps: (a) register child repos, (b) scaffold child-repo agent files, (c) set maintainer(s) in `MAINTAINERS.json`, (d) choose optional hooks, (e) seed `taxonomy.yaml` and research, (f) review/customize agent roles. Each completed step is removed from `.needs-init`, so the wizard is re-entrant if interrupted.

The template footprint is intentionally lean: `AGENT.md`, `CLAUDE.md`, `CODEX.md`, `MAINTAINERS.json`, `agents/`, `scripts/`, `knowledge/`, `notes/`, `logs/`, `local/`, `repos/`, `.claude/`, `.gitignore`. A new project starts with the governance scaffold and nothing else — no inherited progress logs, handoffs, or design components from upstream.

## Key Points

- Quick mode: `./init-project.sh <name> <path>` — structure scaffolded in <5s, no prompts
- Guided mode: `./init-project.sh <name> <path> --guided` — same scaffold + `.needs-init` marker
- `.needs-init` JSON tracks 6 remaining steps; `init-wizard` skill consumes it
- `init-wizard` walks: child repos, child-agent scaffolding, maintainer, hooks, knowledge, roles
- Template placeholders: `{{PROJECT_NAME}}`, `{{PROJECT_ROOT}}` (substituted at init)
- Copied: `AGENT.md`, `CLAUDE.md`, `CODEX.md`, `agents/`, `scripts/`, `knowledge/`, `notes/`, `logs/`, `local/`, `repos/`, `.claude/`
- `register-repo.sh` integrates with `init-wizard` step (a) for child repo discovery
- `health_check.sh` available for post-init verification
- After init, run `scripts/hooks/lib/tools-init.sh` and `scripts/validate/update_hooks_lock.sh` (see [Security & Hardening](security-hardening.md))

## See Also

- [`init-project.sh`](../../init-project.sh) — scaffolding entry point
- [`agents/skills/init-wizard/SKILL.md`](../../agents/skills/init-wizard/SKILL.md) — interactive setup walkthrough
- [`scripts/repos/register-repo.sh`](../../scripts/repos/register-repo.sh) — child repo registration
- [`scripts/session/health_check.sh`](../../scripts/session/health_check.sh) — post-init diagnostics
- [`MAINTAINERS.json`](../../MAINTAINERS.json) — maintainer registry consumed by `init-wizard`
