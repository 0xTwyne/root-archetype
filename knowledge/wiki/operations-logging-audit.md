# Operations: Logging, Audit, and Log Push

**Category**: operations

How session activity is logged, audited, and pushed back to the main branch.

## Summary

Session logging produces an append-only audit trail at `logs/audit/<user>/`. `scripts/utils/agent_log.sh` is the entry point; the `post-tool-use-audit.sh` hook integrates it into the Claude Code lifecycle so every tool call is recorded without agent intervention. Per-user scoping (`logs/audit/<user>/`, `logs/progress/<user>/`, `notes/<user>/`) prevents cross-user collisions structurally — one agent cannot accidentally overwrite another user's notes because the path is namespaced before the agent ever sees it.

Pushing logs back to main uses `scripts/utils/push-logs.sh`: a git-worktree + lockfile pattern that lets a session push log/note changes to `origin/main` without bypassing branch protection. The script creates a temporary worktree from `origin/main`, rsyncs the local log/note tree into it, commits, and pushes. The worktree is cleaned up after each run; stale-worktree detection via `git worktree prune` handles cross-environment paths (host vs container).

Session-start and session-end hooks write logs/notes to the configured log repo (`--log-repo` flag at init) with fallback to project root, supporting both single-repo (legacy) and split-mode layouts.

## Key Points

- Append-only audit logs in `logs/audit/<user>/` — every Claude Code tool call recorded
- `scripts/utils/agent_log.sh` is the logging entry point; `post-tool-use-audit.sh` hook drives it
- Per-user scoping eliminates cross-user write collisions structurally
- `scripts/utils/push-logs.sh` uses git worktree + lockfile to push log-only commits to main
- `git worktree prune` + validity check before checkout handles stale worktrees across host/container
- `--log-repo` flag at init splits logs into `repos/<project>-logs/`; default is single-repo
- Session-start writes `.session-identity` (gitignored); session-end pushes logs and progress

## See Also

- [`scripts/utils/agent_log.sh`](../../scripts/utils/agent_log.sh) — logging entry point
- [`scripts/utils/push-logs.sh`](../../scripts/utils/push-logs.sh) — log-only main push via worktree
- [`scripts/hooks/post-tool-use-audit.sh`](../../scripts/hooks/post-tool-use-audit.sh) — audit-trail hook
- [`scripts/hooks/session-start.sh`](../../scripts/hooks/session-start.sh) and [`session-end.sh`](../../scripts/hooks/session-end.sh) — lifecycle hooks
- [`scripts/hooks/lib/log-repo.sh`](../../scripts/hooks/lib/log-repo.sh) — log repo path resolution
- [Knowledge Compilation Pipeline](knowledge-compilation-pipeline.md) — how these logs feed into the wiki
