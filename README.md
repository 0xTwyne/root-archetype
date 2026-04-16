# {{PROJECT_NAME}} — Root Governance Repository

An archetype for creating governed, multi-repo workspaces where AI agents
(Claude Code, Codex, or others) operate under shared policy, hooks, and
knowledge management. No application code lives here — this repo coordinates
child repos that contain it.

## How It Works

1. **Clone this archetype** and run `init-project.sh` to scaffold a new governance root
2. **Register child repos** — your actual application code — under this root
3. **AI agents read `AGENT.md`** (engine-neutral) for operating instructions, then
   engine-specific pointers (`CLAUDE.md`, `CODEX.md`) wire hooks and skills

## Prerequisites

- bash, git, python3, jq
- Optional: [GitHub CLI](https://cli.github.com/) (`gh`) for session PRs and user detection

## Quick Start

```bash
# Create a new governed project (quick mode)
./init-project.sh my-project /path/to/project --email "you@example.com"

# Or with child repos and guided wizard
./init-project.sh my-project /path/to/project \
  --repos "api:/path/to/api,web:/path/to/web" \
  --guided

# If already initialized, register more repos later
scripts/repos/register-repo.sh my-lib /path/to/my-lib --purpose "shared library"
```

**Quick mode** scaffolds the full structure and you configure manually.
**Guided mode** (`--guided`) also drops a `.needs-init` marker — on the next
agent session, the init wizard walks through repo registration, maintainer setup,
hook selection, knowledge seeding, and role customization interactively.

## Repository Structure

```
├── AGENT.md               # Engine-neutral agent instructions (primary)
├── CLAUDE.md              # Claude Code engine wiring (generated, gitignored)
├── CODEX.md               # OpenAI Codex engine wiring (generated, gitignored)
├── MAINTAINERS.json       # Who can modify protected files
├── agents/
│   ├── shared/            # Cross-cutting policy (constraints, standards, workflows)
│   ├── roles/             # Role overlays (6-section schema per role)
│   └── skills/            # Engine-neutral skill definitions + catalog
├── scripts/
│   ├── hooks/             # All hooks (5 default, 8 optional) + lib/
│   ├── validate/          # Governance validators
│   ├── session/           # Session lifecycle
│   ├── repos/             # Child repo management
│   └── utils/             # Logging, analysis
├── .claude/
│   ├── settings.json      # Hook wiring (points to scripts/hooks/)
│   └── skills/            # Thin wrappers for Claude Code discovery
├── knowledge/             # Compiled wiki + research intake
├── notes/                 # Per-user notes, plans, handoffs
├── logs/                  # Audit trail + per-user progress
├── secrets/               # Protected paths (contents gitignored)
├── local/                 # Per-machine customization (gitignored)
└── repos/                 # Symlinks to registered child repos
```

## Hooks

Hooks enforce policy during agent sessions. Five are wired by default in
`.claude/settings.json`:

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart | Resolve user, branch, load context |
| `session-end.sh` | SessionEnd | Write progress, commit, push |
| `check_secrets_read.sh` | PreToolUse (Read) | Block reads of protected paths |
| `check_filesystem_path.sh` | PreToolUse (Write) | Prevent writes outside project |
| `post-tool-use-audit.sh` | PostToolUse | Append-only audit trail |

Eight more ship in `scripts/hooks/` but are not wired by default (edit guard,
schema enforcement, correction detection, etc.). Enable them via
`.claude/settings.json` or the init wizard. See `scripts/hooks/README.md`.

## Skills

Skills are reusable methodology definitions that agents load on demand.
Canonical definitions live in `agents/skills/`, with a catalog at
`agents/skills/DISCOVERY.md`.

| Skill | Trigger |
|-------|---------|
| `project-wiki` | "lint KB", "compile wiki", "what do we know about X" |
| `research-intake` | "research intake", "ingest this" |
| `safe-commit` | "safe commit", "commit with checks" |
| `simplify` | "simplify", "review code", "clean up" |
| `new-skill` | "create a skill", "scaffold skill" |
| `new-handoff` | "new handoff", "track work item" |
| `init-wizard` | Automatic when `.needs-init` exists |
| `wrap-up` | "wrap up", mid-session save, checkpoint progress |

## Knowledge Management

Per-user streams (notes, progress logs) flow into compiled shared knowledge.
No session starts from zero — every agent reads from the compiled wiki.

```
Session A (dev 1)          Session B (dev 2)
  notes/dev1/                notes/dev2/
  progress logs              handoff docs
       \                        /
        v                      v
    ┌──────────────────────────────┐
    │   /project-wiki compile      │
    │   synthesize + deduplicate   │
    └──────────┬───────────────────┘
               v
       knowledge/wiki/
    (compiled, cross-user,
     cited, queryable)
               ^
               |
    ┌──────────┴───────────────────┐
    │   /research-intake            │
    │   external papers, URLs,      │
    │   benchmarks → deep-dives/    │
    └──────────────────────────────┘
```

- **Write to**: `notes/<your-username>/`, `logs/progress/<your-username>/`
- **Compile via**: `/project-wiki compile` → outputs to `knowledge/wiki/`
- **Ingest external sources**: `/research-intake` → `knowledge/research/`

See `notes/README.md` for conventions.

## Child Repo Management

The root repo governs child repos hierarchically. Shared policy, roles, and
knowledge flow downward. Each child repo stays self-contained — the root adds
cross-repo awareness, not coupling.

```
        ┌─────────────────────────┐
        │     root-archetype       │
        │  shared policy & roles   │
        │  knowledge/wiki/         │
        │  agents/registry.json    │
        └──┬────────┬────────┬────┘
           │        │        │
     ┌─────┴──┐ ┌───┴────┐ ┌─┴──────┐
     │  api/  │ │  web/  │ │ infra/ │
     │AGENT   │ │AGENT   │ │AGENT   │
     │.md     │ │.md     │ │.md     │
     └────────┘ └────────┘ └────────┘
     child repo  child repo  child repo
```

```bash
scripts/repos/register-repo.sh <name> <path>   # Register (symlinks in repos/)
scripts/repos/scan-agents.sh                     # Discover agents across repos
scripts/repos/sync-repos.sh                      # Pull all registered repos
```

Registered repos get a seeded `CLAUDE.md` and agent role file if they don't
already have one. The root `AGENT.md` repository map updates automatically.

> **Note**: `CLAUDE.md` and `CODEX.md` are generated by `scripts/utils/generate-engine.sh`
> (called during `init-project.sh`) and are gitignored. Only `AGENT.md` is committed.

## Validation

```bash
python3 scripts/validate/validate_agents_structure.py    # Role file schema
python3 scripts/validate/validate_document_drift.py      # Structural integrity
python3 scripts/validate/validate_claude_md_consistency.py  # Instruction file refs
python3 scripts/validate/validate_skills.py              # Skill standards
```

## License

MIT
