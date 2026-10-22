# Utility Scripts

Shared utilities used by hooks, skills, and session lifecycle.

| Script | Called by | Purpose |
|--------|-----------|---------|
| `agent_log.sh` | Hooks, skills | Append-only audit trail logging (`agent_session_start`, `agent_session_end`, `agent_warn`) |
| `agent_log_analyze.sh` | Manual | Analyze audit log entries |
| `check_secret_refs.sh` | Manual, CI deploy steps | Check a secret-reference env file: no literal credentials, well-formed `op://` refs; `--resolved` fails on refs left after inject |
| `generate-handoff-index.sh` | `push-logs.sh`, `/project-wiki compile` | Scan `notes/*/handoffs/**/*.md` and regenerate `notes/handoffs/INDEX.md` |
| `push-logs.sh` | `session-end.sh` | Sync logs/notes to main via detached worktree, regenerate handoff index |
