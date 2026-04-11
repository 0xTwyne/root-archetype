# Notes — Per-User Convention

Each team member has a personal directory: `notes/<username>/`

## Structure

```
notes/
├── README.md                  # This file
├── handoffs/
│   ├── INDEX.md               # Auto-generated handoff aggregation
│   └── .gitkeep
└── <username>/
    ├── plans/                 # Active plans and design documents
    ├── research/              # Research observations and notes
    └── handoffs/              # Work handoff documents
        ├── active/            # In-progress handoffs
        └── completed/         # Finished handoffs
```

## Rules

1. Only write to YOUR directory (`notes/<your-username>/`)
2. Never edit another user's files
3. Handoff INDEX.md is auto-generated — don't edit manually

## Lifecycle

1. `session-start.sh` creates your personal directory on first session
2. Use `/new-handoff` to create structured handoff documents
3. `notes/handoffs/INDEX.md` is regenerated automatically on every
   session-end by `scripts/utils/generate-handoff-index.sh` (called
   from `push-logs.sh`). Can also be run manually or via `/project-wiki compile`.
