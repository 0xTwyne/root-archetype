# Multi-Repo Coordination & Child Repos

**Category**: architecture

Registering, syncing, and discovering agents across child repos governed by this root.

## Summary

Root-archetype provides primitives for multi-repo projects: child repos are registered via `scripts/repos/register-repo.sh`, discovered via `scan-agents.sh`, and synced via `sync-repos.sh`. Each child repo is self-contained — it has its own `AGENT.md` and engine-specific wiring — and the root project's `AGENT.md` includes a Repository Map table listing each child's path and purpose.

`init-wizard` step (b) scaffolds child-repo agent files by scanning file structure and key patterns to generate a draft `AGENT.md` for any registered child without an existing one. `register-repo.sh` updates the root's repository map and detects existing child agent files (skipping scaffolding when one is found). `sync-repos.sh` pulls changes from all registered repos.

Repos inside `repos/` are detected as physical directories; external repos are registered as symlinks. Health checks (`scripts/session/health_check.sh`) verify reachability and main-branch state of every registered repo.

## Key Points

- `register-repo.sh`: registers a child repo, updates the repository map in `AGENT.md`, detects existing agent files
- `scan-agents.sh`: discovers agents across the root + every registered child repo
- `sync-repos.sh`: pulls changes from all registered repos
- `init-wizard` step (b): scaffolds draft `AGENT.md` for child repos lacking one
- Repository Map: a table in `AGENT.md` listing repo path, purpose, maintainers
- Each child repo is self-contained (its own `AGENT.md` + engine wiring); the root adds cross-repo awareness, not coupling
- Repos under `repos/` are physical; external repos register as symlinks
- `health_check.sh` verifies child-repo reachability and main-branch state
- Use `--no-scaffold` on `register-repo.sh` to register a repo without seeding agent files

## See Also

- [`scripts/repos/register-repo.sh`](../../scripts/repos/register-repo.sh) — register a child repo
- [`scripts/repos/scan-agents.sh`](../../scripts/repos/scan-agents.sh) — discover agents across repos
- [`scripts/repos/sync-repos.sh`](../../scripts/repos/sync-repos.sh) — pull all registered repos
- [`scripts/session/health_check.sh`](../../scripts/session/health_check.sh) — child-repo health diagnostics
- [`agents/skills/init-wizard/SKILL.md`](../../agents/skills/init-wizard/SKILL.md) — interactive setup that includes child-repo registration
- [Project Initialization](project-initialization.md) — init flow that prepares this multi-repo structure
