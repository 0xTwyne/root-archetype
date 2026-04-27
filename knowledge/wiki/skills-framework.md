# Skills Framework & Design Patterns

**Category**: tooling

Three-level progressive disclosure, trigger-spec descriptions, and how to add your own skills.

## Summary

Skills follow Anthropic's three-level progressive disclosure: Level 1 (YAML frontmatter, always loaded), Level 2 (`SKILL.md` body, loaded when Claude judges relevance), Level 3 (linked `references/`, `scripts/`, `assets/`, on demand). Token cost scales with depth — frontmatter is roughly 50 tokens per skill in every system prompt, so descriptions must earn their keep.

A skill's `description` field is a trigger specification, not a summary. The formula is `[What it does] + [When to use it — specific trigger words] + [When NOT to use it]`. Vague descriptions cause undertriggering (ignored when needed) or overtriggering (loaded for irrelevant queries). Each skill must include a Gotchas section documenting edge cases agents hit in practice — empirically the highest-signal section.

Skills are folders, not files. `SKILL.md` is the entrypoint; `scripts/` holds executables (validators, fetchers); `references/` holds detailed docs (API patterns, schemas); `assets/` holds templates. Skills can compose by referencing other installed skills by name. The `new-skill` meta-skill scaffolds correct structure for any instance-specific skill. Seven skills ship with the archetype: `new-skill`, `new-handoff`, `safe-commit`, `simplify`, `project-wiki`, `research-intake`, `init-wizard`.

## Key Points

- Three-level progressive disclosure: frontmatter (always) → `SKILL.md` (relevant) → `scripts/`/`references/`/`assets/` (on demand)
- `description` field is a trigger spec: `[What] + [When to use — specific words] + [When NOT to use]`
- Gotchas section is highest-signal — documents edge cases agents hit in practice
- Skills are folders (`SKILL.md` + `scripts/` + `references/` + `assets/`), not flat files
- `validate_skills.py` checks frontmatter, description quality, presence of Gotchas
- Skills can compose by referencing other installed skills by name
- Templates in `_templates/skill/` (SKILL.md template + empty subdirectories)
- Verbose instructions raise inference cost ~20% without improving success — keep instruction budget tight
- 7 built-in skills: `new-skill`, `new-handoff`, `safe-commit`, `simplify`, `project-wiki`, `research-intake`, `init-wizard`
- Use `/new-skill` to scaffold an instance-specific skill — it generates the correct structure

## See Also

- [`agents/skills/DISCOVERY.md`](../../agents/skills/DISCOVERY.md) — catalog of installed skills
- [`agents/skills/new-skill/SKILL.md`](../../agents/skills/new-skill/SKILL.md) — meta-skill that scaffolds new skills
- [`scripts/validate/validate_skills.py`](../../scripts/validate/validate_skills.py) — skill structure validator
- [`docs/guides/skills-engineering.md`](../../docs/guides/skills-engineering.md) — local guide on skill design
- [Anthropic skills overview](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) — upstream pattern
