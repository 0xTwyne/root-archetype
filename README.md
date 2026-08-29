# {{PROJECT_NAME}} — Root Governance Repository

An archetype for creating governed, multi-repo workspaces where AI agents
(Claude Code, Codex, or others) operate under shared policy, hooks, and
knowledge management. No application code lives here — this repo coordinates
child repos that contain it.

## How It Works

1. **Clone this archetype** and run `init-project.sh` to scaffold a new governance root
2. **A log repo is created automatically** inside `repos/` for session logs, notes, and handoffs
3. **Register child repos** — your actual application code — under this root
4. **AI agents read `AGENT.md`** (engine-neutral) for operating instructions, then
   engine-specific pointers (`CLAUDE.md`, `CODEX.md`) wire hooks and skills

## Prerequisites

- bash, git, python3, jq
- Optional: [GitHub CLI](https://cli.github.com/) (`gh`) for session PRs and user detection

## Quick Start

```bash
# Create a new governed project (in-place, after cloning the archetype)
git clone <archetype-url> my-project && cd my-project
./init-project.sh my-project

# Or with child repos and guided wizard
./init-project.sh my-project \
  --repos "api:/path/to/api,web:/path/to/web" \
  --guided

# Copy mode (scaffold into a different directory)
./init-project.sh my-project --copy-to /path/to/target

# Custom knowledge repo location (default: repos/<name>-knowledge/)
./init-project.sh my-project --knowledge-repo /path/to/custom-knowledge

# Register more repos later
scripts/repos/register-repo.sh my-lib /path/to/my-lib --purpose "shared library"
```

**Quick mode** scaffolds the full structure and you configure manually.
**Guided mode** (`--guided`) also drops a `.needs-init` marker — on the next
agent session, the init wizard walks through repo registration, maintainer setup,
hook selection, knowledge seeding, and role customization interactively.

## Repository Structure

```
├── AGENT.md               # Engine-neutral agent instructions (primary)
├── CLAUDE.md              # Claude Code engine wiring (tracked)
├── CODEX.md               # OpenAI Codex engine wiring (tracked)
├── MAINTAINERS.json       # Who can modify protected files
├── .claude/               # TRACKED: settings.json, skills/, commands/
├── agents/
│   ├── shared/            # Cross-cutting policy (constraints, standards, workflows)
│   ├── roles/             # Role overlays (6-section schema per role)
│   └── prompt-templates/  # Optional prompt snippets copied to local/ at init
├── scripts/
│   ├── bootstrap.sh       # One-shot setup for a fresh clone (run this first)
│   ├── hooks/             # All hooks (6 wired by default, 16 total) + lib/ + tests/
│   ├── validate/          # Governance validators
│   ├── session/           # Session lifecycle
│   ├── repos/             # Child repo management
│   └── utils/             # Logging, analysis, generation
├── docs/                  # Guides and design notes
├── templates/             # Seed files copied into new knowledge repos
├── knowledge/             # Archetype-internal KB — never copied into spawned
│                          #   projects except taxonomy.yaml (see init-project.sh)
├── logs/                  # Stub — actual data in the knowledge repo
├── notes/                 # Stub — actual data in the knowledge repo
├── repos/
│   ├── <project>-knowledge/  # Knowledge repo (logs, notes, handoffs, compiled wiki)
│   └── <child-repo>/      # Registered application repos (symlink or physical)
├── secrets/               # Protected paths (contents gitignored)
├── local/                 # Per-machine customization (gitignored)
└── tmp/                   # Shared scratch — contents gitignored
```

> **Note**: `CLAUDE.md`, `CODEX.md` and `.claude/` (settings, skills, commands)
> are **tracked in git**. A clone has working hooks and every skill immediately —
> nothing is generated, and adding a skill later reaches collaborators through a
> plain `git pull`. Only `.claude/settings.local.json` stays machine-local.

## Knowledge Repo

Every initialized project gets a dedicated **knowledge repo** at
`repos/<project>-knowledge/`. This is a separate git repository with no branch
protections, so all team members can push session logs freely — even when the
root repo has required reviews or CI gates.

The knowledge repo contains:

| Directory | Contents |
|-----------|----------|
| `logs/audit/<user>/` | Per-user audit trails |
| `logs/progress/<user>/` | Daily session progress reports |
| `logs/agent_audit.log` | Append-only audit trail (JSONL) |
| `notes/<user>/handoffs/` | Work tracking documents (active/completed) |
| `notes/<user>/research/` | Per-member research intake (promoted to master by maintainers) |
| `notes/<user>/facts.md` | Cross-session facts cache |
| `wiki/` | The compiled wiki, shared by all users (INDEX.md, STALENESS.md generated) |

The knowledge repo is registered as a child repo and discovered via
`.archetype-manifest.json` → `log_repo_name` → `repos/<name>`.

## Hooks

Hooks enforce policy during agent sessions. Six are wired by default in
`.claude/settings.json`:

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart | Resolve user, branch, load context |
| `session-end.sh` | SessionEnd | Write progress, push to log repo |
| `check_secrets_read.sh` | PreToolUse (Read) | Block reads of protected paths |
| `check_filesystem_path.sh` | PreToolUse (Write) | Prevent writes outside project |
| `post-tool-use-audit.sh` | PostToolUse | Append-only audit trail |
| `check_clone_destination.sh` | PreToolUse (Bash) | Block clones/worktrees landing outside the project |

Ten more ship in `scripts/hooks/` but are not wired by default (edit guard,
schema enforcement, correction detection, etc.). Enable them via
`.claude/settings.json` or the init wizard. See `scripts/hooks/README.md`.

All hook commands use the `${CLAUDE_PROJECT_DIR:-.}/` prefix for reliable path
resolution regardless of working directory.

## Security Out of the Box

Root-archetype ships defensive measures so that any clone has a working
agent-safety baseline before customization. Full reference:
[`docs/guides/security.md`](docs/guides/security.md).

| Layer | Mechanism | Where |
|-------|-----------|-------|
| **Read-side secret protection** | Block agent reads of protected paths | `scripts/hooks/check_secrets_read.sh` (default-on) |
| **Write-side filesystem boundary** | Prevent writes outside the project tree | `scripts/hooks/check_filesystem_path.sh` (default-on) |
| **Pre-write secret scan** | Scan staged content for credential patterns | `scripts/hooks/pre-edit-guard.sh` + `lib/secret-patterns.txt` |
| **Tool pinning** | Hooks resolve `git`/`jq`/`python3`/… via pinned absolute paths instead of `$PATH` | `scripts/hooks/lib/tools.lock` + `hook_resolve_tool` |
| **Hook/validator drift detection** | sha256-locked tree of `scripts/hooks/` + `scripts/validate/`; tampering fails CI | `HOOKS.lock` + `scripts/validate/validate_hooks_lock.sh` |
| **Dry-run / argv mode** | Print the launch chain (paths, env, tools, planned writes) without side effects | `session-start.sh --argv`, `session_init.sh --argv` |
| **Append-only audit trail** | Every tool call logged | `scripts/hooks/post-tool-use-audit.sh` + `scripts/utils/agent_log.sh` (default-on) |
| **Bounded test execution** | Caps for parallelism/timeouts on agent-issued test runs | `scripts/hooks/check_test_safety.sh` |
| **Schema/structure invariants** | Agent role + skill + doc-drift validators | `scripts/validate/*.py` |
| **Session isolation** | Each session runs on its own branch; identity persisted to `.session-identity` | `scripts/hooks/session-start.sh` |
| **Per-user log/notes scoping** | Cross-session writes routed under `notes/<user>/`, `logs/progress/<user>/` | `lib/log-repo.sh`, `hook_ensure_log_dirs` |
| **Strict mode escape hatch** | `ARCHETYPE_HOOK_TOOLS_STRICT=1` makes unpinned tools fail hard | env var, see `hook_resolve_tool` |

**One-time setup after cloning:**

```bash
scripts/hooks/lib/tools-init.sh        # generate per-installation tools.lock
scripts/validate/update_hooks_lock.sh  # generate HOOKS.lock for this checkout
```

After upgrades or hook edits, treat both as security events — re-run them
deliberately and review the diffs before committing.

## Skills

Skills are reusable methodology definitions that agents load on demand.
Skills live at `.claude/skills/{name}/SKILL.md` — that file is the skill, not a
wrapper. Catalog: `.claude/skills/DISCOVERY.md`.

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

Everyone produces into the knowledge repo — notes, progress reports, research
intake — and the compile step distils those per-user streams into the shared
wiki **in the same repo**. Nothing is compiled into the root repo: the wiki is
data, and data lives where every team member can push.

```
 repos/<project>-knowledge/ (any team member)
┌─────────────────────────────┐
│ notes/<user>/handoffs/      │
│ notes/<user>/plans/         │──┐
│ notes/<user>/research/      │  │
│ logs/progress/<user>/       │  │
└─────────────────────────────┘  │
                                 v
              ┌───────────────────────┐
              │ /project-wiki compile │
              └──────────┬────────────┘
                         v
┌─────────────────────────────┐
│ wiki/                       │  compiled articles + INDEX.md + STALENESS.md
│ (same repo, shared by all)  │  categories from knowledge/taxonomy.yaml (root)
└─────────────────────────────┘
```

- **Write to**: `<knowledge-repo>/notes/<your-username>/`, `<knowledge-repo>/logs/progress/<your-username>/`
- **Research intake**: `/research-intake` → `<knowledge-repo>/notes/<username>/research/`
- **Compile**: `/project-wiki compile` → `<knowledge-repo>/wiki/` (never the root repo)

## Wiki — How to Use, Modify, and Personalize Root-Archetype

[`knowledge/wiki/`](knowledge/wiki/) is reference documentation about
root-archetype itself, for anyone cloning it to build a new root repo. It is
**archetype-internal**: `init-project.sh` excludes it (and everything else under
`knowledge/` except `taxonomy.yaml`) from spawned projects, so this directory is
also a safe home for progress and handoffs on archetype development. Each page
indexes the source-of-truth files in this repo (`scripts/`, `.claude/skills/`,
`docs/guides/`) and links external references where useful.

| Page | Topic |
|------|-------|
| [Project Initialization & Setup](knowledge/wiki/project-initialization.md) | `init-project.sh` quick / guided modes, the `init-wizard` skill |
| [Engine-Neutral Architecture](knowledge/wiki/engine-neutral-architecture.md) | how the same scaffold runs under Claude Code, Codex, or future engines |
| [Hook System & Governance Enforcement](knowledge/wiki/hook-system-governance.md) | hook events, default vs optional, CWD-independent invocation |
| [Security & Hardening](knowledge/wiki/security-hardening.md) | tool pinning, drift detection, dry-run mode, threat model |
| [Agent Roles & Engineering Standards](knowledge/wiki/agent-roles-standards.md) | 6-section role schema, instruction budget, harness patterns |
| [Documentation & Governance Hygiene](knowledge/wiki/documentation-governance.md) | `AGENT.md` / README conventions, KB linting, drift validators |
| [Knowledge Compilation Pipeline](knowledge/wiki/knowledge-compilation-pipeline.md) | two-tier flow from per-user logs/notes to compiled wiki |
| [Operations: Logging, Audit, and Log Push](knowledge/wiki/operations-logging-audit.md) | audit trail, `agent_log.sh`, `push-logs.sh` worktree pattern |
| [Multi-Repo Coordination & Child Repos](knowledge/wiki/multi-repo-coordination.md) | registering, syncing, discovering agents across governed children |
| [Skills Framework & Design Patterns](knowledge/wiki/skills-framework.md) | progressive disclosure, trigger-spec descriptions, adding new skills |

The full index lives at [`knowledge/wiki/README.md`](knowledge/wiki/README.md).

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
scripts/repos/register-repo.sh <name> <path>       # Register a child repo
scripts/repos/register-repo.sh <name> <path> \
  --no-scaffold                                     # Register without agent scaffolding
scripts/repos/scan-agents.sh                        # Discover agents across repos
scripts/repos/sync-repos.sh                         # Pull all registered repos
```

Registered repos get a seeded `CLAUDE.md` and agent role file if they don't
already have one (unless `--no-scaffold` is passed). Repos inside `repos/` are
detected as physical directories; external repos are symlinked.

## Validation

```bash
python3 scripts/validate/validate_agents_structure.py    # Role file schema
python3 scripts/validate/validate_document_drift.py      # Structural integrity
python3 scripts/validate/validate_claude_md_consistency.py  # Instruction file refs
python3 scripts/validate/validate_skills.py              # Skill standards
```

## License

MIT
