# Root-Archetype Wiki

How to use, modify, and personalize root-archetype when building new root repos.
This is reference documentation aimed at people cloning the archetype — not a
session-history record.

## Index

### Getting started
- [Project Initialization & Setup](project-initialization.md) — `init-project.sh` quick / guided modes, the `init-wizard` skill, what each step does
- [Engine-Neutral Architecture](engine-neutral-architecture.md) — how the same scaffold runs under Claude Code, Codex, or any future engine

### Day-to-day governance
- [Hook System & Governance Enforcement](hook-system-governance.md) — Claude Code hook events, default vs optional hooks, CWD-independent invocation
- [Security & Hardening](security-hardening.md) — tool pinning, hook drift detection, dry-run verification, threat model
- [Agent Roles & Engineering Standards](agent-roles-standards.md) — 6-section role schema, instruction budget, harness patterns
- [Documentation & Governance Hygiene](documentation-governance.md) — `AGENT.md` / README conventions, KB linting, drift detection

### Knowledge & operations
- [Knowledge Compilation Pipeline](knowledge-compilation-pipeline.md) — two-tier flow from per-user logs/notes to compiled wiki
- [Operations: Logging, Audit, and Log Push](operations-logging-audit.md) — session audit trail, `agent_log.sh`, `push-logs.sh` worktree pattern

### Multi-repo
- [Multi-Repo Coordination & Child Repos](multi-repo-coordination.md) — registering, syncing, discovering agents across governed child repos

### Tooling & extensibility
- [Skills Framework & Design Patterns](skills-framework.md) — three-level progressive disclosure, trigger-spec descriptions, how to add your own skills

## How this wiki is organized

Each page has:

- **Category** — one of `architecture`, `governance`, `operations`, `tooling`, `research` (see [`taxonomy.yaml`](../taxonomy.yaml))
- **Summary** — 2-3 paragraphs explaining what the system does and why
- **Key Points** — the bullets you'd want to remember after a coffee break
- **See Also** — pointers to the actual code, scripts, and external references

The pages stay short on purpose — they index the source-of-truth files in the
repo (`scripts/`, `agents/skills/`, `docs/guides/`) rather than duplicate them.
When code or docs move, update the page's "See Also" section.
