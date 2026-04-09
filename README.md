# {{PROJECT_NAME}} — Root Governance Repository

Governance umbrella for cross-repo coordination. No application code lives here.

## Quick Start

```bash
# Seed a new project from this archetype
./init-project.sh my-project /path/to/project --repos "app:/path/to/app,lib:/path/to/lib"

# Or if already initialized:
source scripts/utils/agent_log.sh
./scripts/session/session_init.sh
```

## Repository Structure

```
{{PROJECT_NAME}}/
├── agents/              # Agent role definitions (thin-map architecture)
│   ├── shared/          # Cross-cutting policy
│   └── *.md             # Role-specific overlays
├── scripts/
│   ├── hooks/           # Pre/post tool-use enforcement gates
│   ├── validate/        # Governance validators
│   ├── session/         # Session lifecycle management
│   ├── nightshift/      # Autonomous overnight scheduler
│   ├── repos/           # Child repo management
│   └── utils/           # Shared utilities (logging, analysis)
├── secrets/             # Protected secrets (contents gitignored)
├── swarm/               # Swarm coordination primitive
├── .claude/             # Claude Code configuration
│   ├── settings.json    # Hook wiring
│   ├── commands/        # Slash commands
│   └── skills/          # Packaged skills
├── handoffs/            # Cross-repo work tracking
│   ├── active/
│   ├── blocked/
│   ├── completed/
│   └── archived/
├── progress/            # Daily progress (YYYY-MM/YYYY-MM-DD.md)
├── logs/                # Audit trail
├── coordination/        # Cross-repo coordination
└── docs/                # Long-lived documentation
```

## Governance Primitives

- **Hooks**: Pre-tool-use gates (filesystem safety, schema validation, etc.)
- **Validators**: Structural consistency checks
- **Agent System**: Thin-map architecture — shared policy + lean role overlays
- **Secrets Protection**: Config-driven read-blocking hook + sandbox template
- **Audit Logging**: Append-only JSONL with session tracking
- **Swarm Coordination**: SQLite-backed agent coordination with priority scheduling

## Swarm Architecture

The swarm primitive provides multi-agent coordination:
- Agent registration + heartbeat
- Priority work queue (not FIFO — information-gain-aware scheduling)
- Message board (channels + threaded posts)
- Resource locks with TTL
- Experiment scheduler with Bayesian scoring

See `swarm/README.md` for details.

## Child Repo Management

```bash
# Register a child repo
./scripts/repos/register-repo.sh my-app /path/to/my-app

# Discover agents across all repos
./scripts/repos/scan-agents.sh

# Sync all registered repos
./scripts/repos/sync-repos.sh
```

## License

MIT
