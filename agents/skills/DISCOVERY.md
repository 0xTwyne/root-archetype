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
| init-wizard | `agents/skills/init-wizard/` | `.needs-init` detected by session-start hook | Guided project initialization wizard |
| wrap-up | `agents/skills/wrap-up/` | `/wrap-up`, end of session or mid-session checkpoint | Update logs, progress, handoffs, wiki and indexes; survey every repo for unpushed work; push to main |

## Commands

Engine-neutral command definitions live in `agents/commands/`. For Claude Code,
`generate-engine.sh` copies them into `.claude/commands/`. Unlike skills
(methodology files read by agents), commands are step-by-step workflows executed
directly.

**There are currently no commands.** `wrap-up` was one until the wrap-up
methodology was consolidated into the skill above; `agents/commands/wrap-up.md`
is a redirect stub kept for anyone who arrives at the old path.

## Engine-Specific Discovery

- **Claude Code**: `.claude/skills/{name}/SKILL.md` thin wrappers are auto-generated at init time from `agents/skills/` frontmatter. Regenerate with: `bash scripts/utils/generate-engine.sh --engine claude`
- **Codex**: Read `agents/skills/` directly (no wrapper layer)
- **Other engines**: Read this file for the catalog, then load skill content from the paths above
