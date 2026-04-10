# Handoff 1: Structure Cleanup

**Status**: active
**Created**: 2026-04-09
**Priority**: 1 (must complete before all other handoffs)
**Estimated scope**: ~40 delete/move operations, 0 new code

---

## Context

Root-archetype has accumulated ~4,000 lines of non-core features (swarm coordination, GitNexus integration, nightshift scheduler, upstream tooling) that should be external add-ons, not baked into the template. This handoff strips the repo to essentials before the other handoffs restructure what remains.

---

## Prerequisite

None — this is the first handoff.

---

## Tasks

### A. Delete non-core directories and files

Delete these entirely:

| Path | Lines | Reason |
|------|-------|--------|
| `swarm/` (entire directory) | ~2,346 | Extract to standalone package |
| `coordination/` | 0 (empty) | Dead directory |
| `--help/` | ~7 | Accidental artifact (created by shell mistake) |
| `SPEC.md` | 34 | Content folds into `agents/shared/OPERATING_CONSTRAINTS.md` |
| `nightshift.yaml` | 97 | Extract to standalone skill |
| `scripts/nightshift/` (2 files) | ~150 | Extract with nightshift |
| `scripts/upstream/` (3 files) | ~300 | Extract to standalone skill |
| `scripts/utils/swarm_recover.sh` | ~50 | Extract with swarm |
| `scripts/repos/add-dependency.sh` | ~50 | Remove (coupled to `.claude/dependency-map.json`) |
| `_templates/` (entire directory) | ~100 | Templates travel with their respective skills |
| `.claude/skills/swarm/` | ~100 | Extract with swarm |
| `.claude/skills/upstream/` | ~100 | Extract with upstream |
| `.claude/skills/find-skills/` | ~50 | Remove (users install skills via their engine's ecosystem) |
| `.claude/commands/swarm.md` | ~30 | Extract with swarm |
| `.claude/commands/upstream.md` | ~30 | Extract with upstream |
| `.claude/dependency-map.json` | ~10 | Remove (premature for template) |
| `.claude/agent-cost-policy.json` | ~20 | Remove (move concept to `agents/shared/` in Handoff 6) |
| `.claude/repo-toolchains.json` | ~10 | Remove (not core) |
| `.pytest_cache/` | - | Build artifact, should be gitignored |

### B. Move agent role files

```
agents/lead-developer.md      → agents/roles/lead-developer.md
agents/research-engineer.md   → agents/roles/research-engineer.md
agents/safety-reviewer.md     → agents/roles/safety-reviewer.md
```

Update `agents/AGENT_INSTRUCTIONS.md` reference from `agents/*.md` to `agents/roles/*.md`.

### C. Restructure handoffs to per-user model

```
Current:
  handoffs/active/
  handoffs/blocked/
  handoffs/completed/   (5 files)
  handoffs/archived/

Target:
  notes/handoffs/INDEX.md          (shared auto-aggregated index)
  notes/pestopoppa/handoffs/       (per-user handoff storage)
    completed/                     (move existing completed handoffs here)
```

Move `handoffs/completed/*.md` → `notes/pestopoppa/handoffs/completed/`.
Create `notes/handoffs/INDEX.md` as an initially-empty aggregation file.
Delete `handoffs/` directory after migration.

### D. Restructure progress to per-user model

```
Current:
  progress/2026-03/*.md
  progress/2026-04/*.md

Target:
  logs/progress/pestopoppa/2026-03/*.md
  logs/progress/pestopoppa/2026-04/*.md
```

The `logs/progress/` directory already exists with `pestopoppa/` subdirectory. Move content there. Delete top-level `progress/` directory.

### E. Create new directory structure (empty scaffolding)

```
mkdir -p knowledge/wiki/
mkdir -p knowledge/research/deep-dives/
mkdir -p local/skills/
mkdir -p local/hooks/
mkdir -p local/notes/
mkdir -p repos/
```

Create `.gitkeep` files in:
- `knowledge/wiki/.gitkeep`
- `knowledge/research/.gitkeep`
- `local/.gitkeep`
- `repos/.gitkeep`

### F. Clean up .gitignore

Remove these lines/sections:
- `# Swarm state` block (swarm/*.db etc.)
- `# GitNexus indexes` block (.gitnexus/, AGENTS.md)

Add these lines:
- `local/*` + `!local/.gitkeep` + `!local/README.md` (local customization layer)
- `knowledge/research/.last_compile` (compilation state)

### G. Delete `.claude/hooks/` directory

After Handoff 5 consolidates all hooks into `scripts/hooks/`, delete `.claude/hooks/` entirely. **This task is blocked on Handoff 5 — do G last or as part of Handoff 5.**

---

## Acceptance Criteria

1. `swarm/`, `coordination/`, `--help/`, `_templates/`, `scripts/nightshift/`, `scripts/upstream/` do not exist
2. No `nightshift.yaml`, `SPEC.md` in project root
3. Agent role files live under `agents/roles/`
4. `notes/` has per-user structure with handoff subdirectories
5. `logs/progress/` has per-user structure with migrated content
6. `knowledge/`, `local/`, `repos/` directories exist with `.gitkeep`
7. `.gitignore` has no swarm/gitnexus references; has local/ exclusion
8. `.claude/skills/` contains only: `simplify/`, `new-skill/`, `safe-commit/`, `new-handoff/`, `project-wiki/`
9. `.claude/commands/` contains only: `simplify.md`

---

## Risks

- **Swarm extraction**: Some utility in `swarm/` may be referenced by hooks or session scripts. Grep for `swarm` imports/references before deleting.
- **Progress migration**: Ensure git tracks the move (use `git mv`) to preserve history.
- **Handoff migration**: The new per-user model changes the convention. Update any hooks that reference `handoffs/` paths.
