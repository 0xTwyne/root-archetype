# Skills Engineering Guide

How to build effective Claude Code skills for root-archetype instances.

Based on Anthropic's "Complete Guide to Building Skills for Claude" and internal lessons from the Claude Code team.

## Three-Level Progressive Disclosure

Skills minimize token usage through layered loading:

| Level | What | When loaded | Token cost |
|-------|------|-------------|------------|
| 1 | YAML frontmatter | Always (system prompt) | ~50 tokens per skill |
| 2 | SKILL.md body | When Claude thinks skill is relevant | Hundreds of tokens |
| 3 | Linked files (references/, scripts/, assets/) | On demand during execution | Variable |

**Keep Level 1 tight** — every skill's frontmatter is always in context. A bad description wastes tokens on every request.

**Keep Level 2 under 5000 words** — this loads on every trigger. Put detailed docs in Level 3.

## Writing the Description (Level 1)

The `description` field is a trigger specification, not a summary. Formula:

```
[What it does] + [When to use it — specific trigger words] + [When NOT to use it]
```

Good:
```yaml
description: Commit changes with staged-diff secret scanning and branch protection guardrails. Use when user says "safe commit", "safe-commit", or "commit with checks". Do NOT use for regular commits.
```

Bad:
```yaml
description: Helps with commits.
```

See `.claude/skills/new-skill/references/description-guide.md` for more examples.

## Skill Folder Structure

Skills use a dual-path layout:

**Canonical definition** (engine-neutral, full methodology):
```
agents/skills/<skill-name>/
├── SKILL.md              # Full instructions + gotchas
├── references/           # Detailed docs read on demand
├── scripts/              # Executable code
└── assets/               # Templates, example outputs
```

**Engine wrapper** (Claude Code discovery, thin pointer):
```
.claude/skills/<skill-name>/
└── SKILL.md              # Frontmatter + reference to agents/skills/
```

The wrapper just says: `Read and follow the instructions in agents/skills/<name>/SKILL.md`.

See `agents/skills/DISCOVERY.md` for the full skill catalog.
Use the `new-skill` skill to scaffold correctly.

## The Gotchas Section

Every skill must have `## Gotchas`. This is the highest-signal content after the first week of use.

Start with known failure modes. Add a line each time Claude hits an edge case. Example:

```markdown
## Gotchas

- SQLite coordinator.db must not be accessed by multiple processes simultaneously
- Worker count should not exceed available CPU threads / 2
- Stale locks from crashed workers require manual cleanup
```

If no gotchas are known yet:

```markdown
## Gotchas

- No known gotchas yet — add entries here as edge cases are discovered in use
```

## Don't State the Obvious / Don't Railroad

- Skip knowledge Claude already has (git, shell, common tools)
- Focus on what pushes Claude off its default behavior
- Give intent + guardrails, not rigid step-by-step scripts

Bad: `"Step 1: Run git log. Step 2: Run git cherry-pick. Step 3: ..."`

Good: `"Cherry-pick the commit onto a clean branch. Resolve conflicts preserving intent. If it can't land cleanly, explain why."`

## Skill Categories

Map your skill to one of the 9 categories for design guidance:

| # | Category | Example |
|---|----------|---------|
| 1 | Library & API Reference | Gotchas for child repo CLIs |
| 2 | Product Verification | Smoke-test infrastructure |
| 3 | Data Fetching & Analysis | Benchmarks, metrics |
| 4 | Business Process | Handoff creation, lifecycle automation |
| 5 | Code Scaffolding | Skill scaffolding, project init |
| 6 | Code Quality & Review | Adversarial review of changes |
| 7 | CI/CD & Deployment | Commit guardrails |
| 8 | Runbooks | Diagnostic chains |
| 9 | Infrastructure Ops | Server management |

## On-Demand Hooks

Skills can register hooks that activate only when invoked. Use for situational guardrails that would be too aggressive always-on.

## Skill Composition

Skills can reference other skills by name. Claude will invoke them if installed. Design skills to be modular — break large workflows into composable pieces.

## Decision Matrices

If your skill overlaps with another, add a "When to Use What" table in both skills to help Claude disambiguate.

## Measurement

Skill invocations are logged via the `skill_usage_log.sh` hook. Check `logs/skills/invocations.log` to detect:

- **Undertriggering**: Skill doesn't load when it should → add keywords to description
- **Overtriggering**: Skill loads for irrelevant queries → add negative triggers, narrow description

## Validation

Run the skill validator after creating or modifying skills:

```bash
python3 scripts/validate/validate_skills.py
```

It checks frontmatter, naming, description quality, gotchas presence, and structural rules.

## Creating a New Skill

Use the `new-skill` skill: just say "create a new skill" and follow the prompts. Or manually:

1. Create canonical definition at `agents/skills/<name>/SKILL.md`
2. Add YAML frontmatter with name, description
3. Write instructions and gotchas
4. Create thin wrapper at `.claude/skills/<name>/SKILL.md`
5. Add entry to `agents/skills/DISCOVERY.md`
6. Run the validator
