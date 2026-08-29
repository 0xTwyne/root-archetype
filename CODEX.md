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

## Session lifecycle — run these yourself

Claude Code runs these automatically via hooks. Codex has no hooks, but the
scripts do not need them — they need to be invoked. **Run them yourself:**

1. **At the START of every session**, before any other work:
   ```bash
   bash scripts/hooks/session-start.sh </dev/null
   ```
   Creates the `session/<id>_<date>` branch, resolves your identity, prepares
   log directories, and prints session context — read its output.

2. **At the END of every session**, after your last change:
   ```bash
   bash scripts/hooks/session-end.sh </dev/null
   ```
   Pushes logs to the knowledge repo, commits all session work on the session
   branch, pushes it, and opens a PR. Failures are printed loudly — read the
   output and report any WARNING lines to the operator.

Also write a progress log in the knowledge repo —
`repos/<knowledge-repo>/logs/progress/<user>/`, where `<knowledge-repo>` is the
`log_repo_name` in `.archetype-manifest.json` — before ending; see recent
entries there for the format.

Not replicable under Codex: the per-tool-call audit trail (needs harness
callbacks). Codex sessions are audited coarsely via git history and the
session logs above.

## Engine Wiring

- Skills: read directly from `.claude/skills/` (tracked in git, no wrapper layer) —
  check `.claude/skills/DISCOVERY.md` for the catalog and triggers, and follow
  a skill's `SKILL.md` when its trigger matches the task
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

The session lifecycle (branching, end-of-session commit/push, log push) is
covered by the scripts in the "Session lifecycle" section above — run them at
session start and end.
