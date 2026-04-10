# Skill Discovery

Catalog of all available skills with trigger conditions.

| Skill | Path | Trigger | Description |
|-------|------|---------|-------------|
| simplify | `agents/skills/simplify/` | "simplify", "review code", "clean up", "refactor" | Review changed code for reuse and quality |
| safe-commit | `agents/skills/safe-commit/` | "safe commit", "commit with checks" | Secret-scanning commit workflow |
| new-skill | `agents/skills/new-skill/` | "create a skill", "new skill", "scaffold skill" | Skill scaffolding methodology |
| new-handoff | `agents/skills/new-handoff/` | "new handoff", "create handoff", "track work item" | Handoff document creation |
| project-wiki | `agents/skills/project-wiki/` | "lint KB", "check KB health", "what do we know about" | Wiki compilation and maintenance |
| research-intake | `agents/skills/research-intake/` | "research intake", "ingest this", "add to knowledge base" | Ingest external sources into structured KB |
| find-skills | `agents/skills/find-skills/` | "find a skill for X", "search skills" | Discover and install skills from ecosystem |
| upstream | `agents/skills/upstream/` | "upstream this change" | Contribute instance changes back to archetype |
| swarm | `agents/skills/swarm/` | "swarm status", "claim work" | Swarm coordination operations |

## Engine-Specific Discovery

- **Claude Code**: `.claude/skills/{name}/SKILL.md` thin wrappers (frontmatter + reference to engine-neutral content)
- **Codex**: Read `agents/skills/` directly
- **Other engines**: Read this file for the catalog, then load skill content from the paths above

## Adding a Skill

1. Create canonical definition at `agents/skills/<name>/SKILL.md`
2. Create thin wrapper at `.claude/skills/<name>/SKILL.md` pointing to the canonical definition
3. Add an entry to this catalog
4. Run `python3 scripts/validate/validate_skills.py` to verify
