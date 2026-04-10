# Handoff 7: Documentation

**Status**: active
**Created**: 2026-04-09
**Priority**: 7 (final handoff — depends on all others)
**Estimated scope**: 4 file rewrites, 2 new files

---

## Context

After all structural changes are complete, documentation needs to reflect the new architecture. This is the last handoff because it documents the final state.

---

## Prerequisites

- All Handoffs 1-6 complete

---

## Tasks

### A. Rewrite `README.md`

Current README (82 lines) references old structure. Rewrite for new architecture:

```markdown
# {{PROJECT_NAME}}

Governance root repository for multi-repo project coordination.

## Quick Start

```bash
# Create a new project from this template
./init-project.sh my-project /path/to/project

# Or with guided setup
./init-project.sh my-project /path/to/project --guided
```

## Architecture

```
AGENT.md          ← Engine-neutral agent instructions (THE primary file)
CLAUDE.md         ← Claude Code wiring → references AGENT.md
CODEX.md          ← Codex wiring → references AGENT.md
agents/           ← Agent knowledge (roles, shared policy, skills)
scripts/hooks/    ← Safety and lifecycle hooks
scripts/repos/    ← Child repo management
knowledge/        ← Compiled shared knowledge
notes/            ← Per-user notes and handoffs
local/            ← Personal customization (gitignored)
```

## Engine Support

This template works with any AI coding engine:
- **Claude Code**: Full support via CLAUDE.md + .claude/ wiring
- **Codex**: Basic support via CODEX.md
- **Others**: Read AGENT.md directly

## Documentation

- `agents/README.md` — Agent system overview
- `agents/skills/DISCOVERY.md` — Available skills catalog
- `scripts/hooks/README.md` — Hook documentation
- `local/README.md` — Local customization guide
- `notes/README.md` — Per-user notes convention
```

### B. Write `local/README.md`

```markdown
# Local Customization

This directory is gitignored (except this README and .gitkeep).
Use it for personal, machine-specific configuration.

## Structure

- `skills/` — Personal skills and MCP server configs
- `hooks/` — Personal hooks (linters, formatters, IDE integrations)
- `notes/` — Truly personal scratchpad (not committed anywhere)
- `config/` — Engine-specific overrides

## Examples

- Custom MCP server for your IDE
- Personal commit hook for your coding style
- Shell alias skill you use across projects

## Discovery

AGENT.md references `local/skills/` as a skill discovery path.
Engine wiring files can auto-discover personal hooks here.
Nothing in this directory affects other team members.
```

### C. Update `docs/guides/skills-engineering.md`

Update for new skill architecture:
- Skills live in `agents/skills/{name}/SKILL.md` (engine-neutral)
- Claude wrappers in `.claude/skills/{name}/SKILL.md` (thin pointers)
- Skill catalog in `agents/skills/DISCOVERY.md`
- Remove references to `_templates/skill/` (deleted)
- Reference `agents/skills/new-skill/SKILL.md` for scaffolding guidance

### D. Remove GitNexus documentation

Verify that all GitNexus references are gone from:
- `AGENT.md` (shouldn't have any — new file)
- `CLAUDE.md` (rewritten — shouldn't have any)
- `README.md` (rewriting removes them)
- `scripts/repos/sync-repos.sh` — remove `--index` flag and gitnexus calls if present

### E. Verify no stale cross-references

Run a comprehensive grep across the entire repo for references to deleted components:

```bash
# Should all return 0 results
grep -r "swarm" --include='*.md' --include='*.sh' --include='*.py' --include='*.json' .
grep -r "gitnexus\|GitNexus" --include='*.md' --include='*.sh' --include='*.py' .
grep -r "nightshift" --include='*.md' --include='*.sh' --include='*.py' --include='*.yaml' .
grep -r "_templates" --include='*.md' --include='*.sh' --include='*.py' .
grep -r "\.claude/hooks/" --include='*.md' --include='*.sh' --include='*.py' --include='*.json' .
grep -r "dependency-map" --include='*.md' --include='*.sh' --include='*.py' --include='*.json' .
grep -r "SPEC\.md" --include='*.md' --include='*.sh' --include='*.py' .
```

Any hits must be resolved (updated or removed).

---

## Acceptance Criteria

1. `README.md` reflects new architecture, no old references
2. `local/README.md` exists with customization guide
3. `docs/guides/skills-engineering.md` updated for new skill paths
4. Zero grep hits for deleted component names across all tracked files
5. All cross-references between files are valid (referenced paths exist)
6. No documentation references `.claude/hooks/` (all now `scripts/hooks/`)

---

## Risks

- **Documentation drift**: Once documentation is complete, it can drift as the repo evolves. The `validate_document_drift.py` validator (updated in Handoff 6) should catch major drift. Consider adding key paths to its watch list.
- **README as template**: README.md uses `{{TEMPLATE}}` placeholders that `init-project.sh` fills. Ensure the template version reads well both as a template (in the archetype) and after substitution (in generated projects).
