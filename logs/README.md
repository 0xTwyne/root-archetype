# Logs

This directory is a **stub** in the root governance repo. Actual session logs,
audit trails, and progress reports live in the **log repo**.

## Where is the log repo?

```bash
jq -r '.log_repo_name' .archetype-manifest.json
# Then look in repos/<name>/logs/
```

## Log repo structure

```
<log-repo>/logs/
├── .current_session       # Active session ID
├── agent_audit.log        # Append-only audit trail (JSONL)
├── audit/<username>/      # Per-user audit logs
├── progress/<username>/   # Per-user session progress reports
│   └── YYYY-MM-DD.md     # Daily progress
└── skills/
    └── invocations.log    # Skill usage tracking
```

## Conventions

- **Append-only**: audit trail and progress reports are never overwritten
- **Per-user isolation**: hooks enforce each user can only write to their own directories
- **Provenance**: progress reports include source repo and branch context
- **Auto-push**: session-end hook commits and pushes to the log repo automatically
