# Notes

This directory is a **stub** in the root governance repo. Per-user notes,
handoffs, plans, and facts live in the **log repo**.

## Where is the log repo?

```bash
jq -r '.log_repo_name' .archetype-manifest.json
# Then look in repos/<name>/notes/
```

## Log repo notes structure

```
<log-repo>/notes/
├── <username>/
│   ├── plans/             # Session plans and design documents
│   ├── handoffs/          # Work handoff documents
│   │   ├── active/        # In-progress handoffs
│   │   └── completed/     # Finished handoffs
│   └── facts.md           # Cross-session facts cache
└── handoffs/
    └── INDEX.md           # Auto-generated aggregate index
```

## Rules

1. Only write to YOUR directory (`notes/<your-username>/`)
2. Never edit another user's files
3. Handoff INDEX.md is auto-generated — don't edit manually
4. Use `/new-handoff` to create structured handoff documents
