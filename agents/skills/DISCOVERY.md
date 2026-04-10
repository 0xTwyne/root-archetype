# Skill Discovery

Catalog of all available skills with trigger conditions.

| Skill | Path | Trigger | Description |
|-------|------|---------|-------------|
| simplify | `agents/skills/simplify/` | "simplify", "review code", "clean up", "refactor" | Review changed code for reuse and quality |
| safe-commit | `agents/skills/safe-commit/` | "safe commit", "commit with checks" | Secret-scanning commit workflow |
| new-skill | `agents/skills/new-skill/` | "create a skill", "new skill", "scaffold skill" | Skill scaffolding methodology |
| new-handoff | `agents/skills/new-handoff/` | "new handoff", "create handoff", "track work item" | Handoff document creation |
| project-wiki | `agents/skills/project-wiki/` | "lint KB", "check KB health", "what do we know about", "compile wiki" | Wiki compilation and maintenance |
| research-intake | `agents/skills/research-intake/` | "research intake", "ingest this", "add to knowledge base" | Ingest external sources into structured KB |

## Engine-Specific Discovery

- **Claude Code**: `.claude/skills/{name}/SKILL.md` thin wrappers (frontmatter + reference to engine-neutral content)
- **Codex**: Read `agents/skills/` directly
- **Other engines**: Read this file for the catalog, then load skill content from the paths above
