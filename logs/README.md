# Logs — Per-Instance Convention

Session hooks create and maintain log files automatically.
No manual setup is required.

## Structure

```
logs/
├── .current_session       # Active session ID (written by session-start hook)
├── agent_audit.log        # Append-only audit trail (written by post-tool-use hook)
├── audit/<username>/      # Per-user audit logs (created by session-start hook)
└── progress/<username>/   # Per-user session progress reports
    └── YYYY-MM-DD.md      # Daily progress (written by session-end hook or manually)
```

## Conventions

- **audit trail**: `agent_audit.log` is append-only. Hooks write structured
  JSON or timestamped entries. Never truncate or edit.
- **progress reports**: One file per day per user. Summarize what was done,
  decisions made, and open items.
- **per-user isolation**: Hooks enforce that each user can only write to
  their own `audit/<username>/` and `progress/<username>/` directories.

## Lifecycle

1. `session-start.sh` creates per-user directories and writes `.current_session`
2. `post-tool-use-audit.sh` appends to `agent_audit.log`
3. `session-end.sh` writes or updates the daily progress report
4. `push-logs.sh` syncs logs/notes to main and regenerates `notes/handoffs/INDEX.md`
