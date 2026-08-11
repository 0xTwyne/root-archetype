# Codex Configuration

> Primary instructions: read `AGENT.md` in this directory.
> This file contains Codex/OpenAI-specific wiring only.

## First run in a fresh clone

Codex has no session hooks, so nothing sets this project up automatically.
If `repos/` is missing child repos or `agents/registry.json` is absent, run:

```bash
bash scripts/bootstrap.sh --engine codex
```

It clones the child repos listed in `repos/repos.json`, rebuilds the agent
registry, and verifies the result. Safe to re-run.

## Engine Wiring

- Skills: read directly from `agents/skills/` (no wrapper layer needed)
- Agent roles: `agents/roles/*.md`
- Shared policy: `agents/shared/*.md`

## Hooks and guards

Codex does not support session hook wiring, so the Claude Code PreToolUse
guards in `scripts/hooks/` do not run here. The engine-agnostic layer does:

- **Git pre-commit** (`scripts/githooks/pre-commit`, installed by bootstrap via
  `core.hooksPath`): blocks committing protected paths and secret-bearing
  diffs. Applies to every git client, including Codex sessions.
- **CI backstop** (`.github/workflows/protected-paths.yml`): fails any push
  that adds protected files, even if local hooks were bypassed.

Conventions that hooks automate under Claude Code are manual here: create a
`session/<id>_<date>` branch before working, commit and push your work at
session end, and write a progress log in the knowledge repo.
