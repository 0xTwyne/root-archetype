---
name: new-skill
description: Scaffold a new Claude Code skill with correct folder structure, YAML frontmatter, gotchas section, and progressive disclosure. Use when user says "create a skill", "new skill", "scaffold skill", "add a skill", or wants to build a reusable capability. Do NOT use when user wants to edit an existing skill.
---

# New Skill Scaffolding

Create a new skill that follows Anthropic's best practices for Claude Code skills engineering.

## What to do

When the user wants a new skill:

1. Ask for the skill **name** (kebab-case, e.g. `deploy-check`) and a one-sentence **purpose** if not already clear from context.

2. Create the skill directory and files in the engine-neutral location:
   ```
   agents/skills/<name>/
   ├── SKILL.md
   ├── references/
   ├── scripts/
   └── assets/       (only if needed)
   ```
   Then regenerate engine wrappers: `bash scripts/utils/generate-engine.sh --engine claude`

3. Write the SKILL.md with proper YAML frontmatter. The **description** field is critical — it's not a summary, it's a trigger specification. Follow this formula:
   ```
   [What it does] + [When to use it — specific keywords/phrases] + [When NOT to use it]
   ```

4. Include a `## Gotchas` section with at least one entry. If none are known yet, add a placeholder:
   ```markdown
   ## Gotchas
   - No known gotchas yet — add entries here as edge cases are discovered in use
   ```

5. Run the skill validator to confirm the new skill passes:
   ```bash
   python3 scripts/validate/validate_skills.py
   ```

6. If the skill overlaps with an existing skill, add a **When to Use What** decision matrix in both skills.

7. (Optional) Create `tests/triggers.md` with example prompts that should and should not activate the skill. This helps refine the description field over time.

## Description field reference

Read `references/description-guide.md` for the full description formula with good and bad examples.

## Gotchas

- Skill name must be kebab-case and match the folder name exactly — the validator enforces this
- Description must contain a trigger phrase like "Use when" — without it Claude won't know when to activate the skill
- Do not put a README.md inside the skill folder — only SKILL.md is recognized
- Keep SKILL.md body under 5000 words — this is Level 2 content loaded on every trigger, bloat wastes tokens
- The `assets/` directory is optional — only create it if the skill needs templates or example outputs
- If the skill needs tool restrictions, use the `allowed-tools` frontmatter field with `Tool(pattern)` syntax
- The `tests/triggers.md` file is optional — only create it if the skill has non-obvious trigger boundaries. It's a documentation artifact for human review, not an automated test suite
