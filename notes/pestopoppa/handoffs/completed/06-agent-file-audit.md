# Handoff 6: Agent File Audit

**Status**: completed
**Created**: 2026-04-09
**Priority**: 6 (depends on Handoffs 1, 2, 5)
**Estimated scope**: review + edit ~8 agent files, update validators

---

## Context

After the structural changes from Handoffs 1-5, the agent files (`agents/shared/`, `agents/roles/`, `agents/AGENT_INSTRUCTIONS.md`, `agents/README.md`) need review for:
1. Stale references to deleted components (swarm, gitnexus, upstream, etc.)
2. Engine-specific language that should be engine-neutral
3. Modularity: clear separation of shared policy → role overlay → skill methodology
4. Validator scope reduction (remove references to deleted files)

---

## Prerequisites

- Handoff 1 complete (deletions done)
- Handoff 2 complete (AGENT.md and skill structure settled)
- Handoff 5 complete (hooks consolidated)

---

## Tasks

### A. Update `agents/AGENT_INSTRUCTIONS.md`

Current file (38 lines) references:
- `agents/*.md` → change to `agents/roles/*.md`
- "Swarm Participation" section (lines 39-46) → **delete entirely**
- "Output Contract" references to handoff documents → update paths to `notes/<user>/handoffs/`

### B. Update `agents/README.md`

Current file (39 lines) references:
- `agents/*.md` → change to `agents/roles/*.md`
- Add reference to `agents/skills/` and `agents/skills/DISCOVERY.md`
- Update "Adding a New Role" instructions for new path structure
- Add section on skills discovery

### C. Review `agents/shared/OPERATING_CONSTRAINTS.md`

Check for:
- References to swarm coordination → remove
- References to `.claude/` paths → make engine-neutral where possible
- Fold in relevant content from deleted `SPEC.md` (34 lines about operating constraints)

### D. Review `agents/shared/ENGINEERING_STANDARDS.md`

Check for:
- Engine-specific language → neutralize
- References to deleted components → remove
- Ensure standards apply universally to any AI engine

### E. Review `agents/shared/WORKFLOWS.md`

Check for:
- Swarm workflow references → remove
- Upstream workflow references → remove
- Nightshift references → remove
- Update handoff workflow for per-user model
- Update progress reporting workflow for per-user paths

### F. Review agent role files

For each role in `agents/roles/`:
- `lead-developer.md` — remove swarm/gitnexus references, ensure 6-section schema
- `research-engineer.md` — remove swarm references, ensure 6-section schema
- `safety-reviewer.md` — remove swarm references, ensure 6-section schema

All role files must use engine-neutral language:
- ❌ "Use Claude Code's Read tool"
- ✅ "Read the file to understand..."

### G. Update validators

#### `scripts/validate/validate_agents_structure.py`
- Update to look in `agents/roles/` instead of `agents/*.md`
- Ensure it validates the 6-section schema correctly for new paths

#### `scripts/validate/validate_agents_references.py`
- Update reference targets for new structure
- Remove validation of deleted files (swarm, dependency-map, etc.)

#### `scripts/validate/validate_claude_md_consistency.py`
- CLAUDE.md is now a thin pointer — validator should check it references AGENT.md
- May need to validate AGENT.md content instead/additionally

#### `scripts/validate/validate_document_drift.py`
- Remove all references to deleted files from its drift detection targets
- Add new files (AGENT.md, CODEX.md, MAINTAINERS.json) to its watch list

#### `scripts/validate/validate_skills.py`
- Update skill paths: primary content in `agents/skills/`, wrappers in `.claude/skills/`
- Validate that each `.claude/skills/` wrapper references its `agents/skills/` counterpart

### H. Move cost policy concept

`agents-cost-policy.json` is deleted in Handoff 1. If its concept (agent cost limits) is worth preserving:
- Add a section to `agents/shared/OPERATING_CONSTRAINTS.md` about cost awareness
- Use natural language rather than JSON configuration

---

## Acceptance Criteria

1. Zero references to `swarm` anywhere in `agents/` files (grep test)
2. Zero references to `gitnexus` or `GitNexus` in `agents/` files
3. Zero references to `nightshift` in `agents/` files
4. Zero references to `upstream` (as a feature, not as git concept) in `agents/` files
5. `agents/AGENT_INSTRUCTIONS.md` references `agents/roles/*.md`
6. All 3 role files pass 6-section schema validation
7. All role files are engine-neutral (no Claude/Codex-specific language)
8. All 5 validators updated for new structure and pass on the restructured repo
9. `SPEC.md` content preserved in `agents/shared/OPERATING_CONSTRAINTS.md`

---

## Risks

- **Validator regression**: Updating validators to new paths might break validation on existing instance repos that haven't been migrated. Validators should be tolerant of both old and new structures, or clearly document they require the new structure.
- **Engine-neutral language**: Some role workflows reference specific tool capabilities. Keep them descriptive ("search the codebase for...") rather than prescriptive ("use the Grep tool to...").
