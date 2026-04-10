---
name: init-wizard
description: Guided project initialization wizard. Use when .needs-init exists in project root (detected by session-start hook). Do NOT use on already-initialized projects. Walks through 6 interactive setup steps.
---

# Init Wizard

Guided project initialization wizard for new archetype instances.

## Trigger

`.needs-init` file exists in project root (detected by session-start hook).

## Steps

### Step a: Register child repos

- Ask user for child repo paths and purposes
- Run `scripts/repos/register-repo.sh` for each
- Update `AGENT.md` repository map table

### Step b: Child repo agent scaffolding

- For each registered child repo WITHOUT an AGENT.md:
  - Scan: file structure, languages, key patterns
  - Generate draft AGENT.md for the child repo
  - Present to user for review/edit
  - On approval: write to child repo
- For repos WITH existing agent files: note and skip

### Step c: Set maintainer(s)

- Ask for maintainer email(s)
- Write `MAINTAINERS.json` with provided emails
- Optionally set per-child-repo maintainers

### Step d: Choose hooks

Present menu of available hooks:

| Hook | Default | Description |
|------|---------|-------------|
| session-start.sh | ON | Session lifecycle + .needs-init detection |
| session-end.sh | ON | Session lifecycle + progress report |
| check_secrets_read.sh | ON | Blocks reads of protected paths |
| check_filesystem_path.sh | ON | Prevents writes outside project |
| post-tool-use-audit.sh | ON | Audit trail logging |
| check_test_safety.sh | OFF | Bounded test parallelism |
| agents_schema_guard.sh | OFF | 6-section schema enforcement |
| pre-edit-guard.sh | OFF | Edit policy enforcement |
| correction-detection.sh | OFF | User correction learning |

Wire selected hooks into `.claude/settings.json`.

### Step e: Knowledge setup

- Ask for existing docs/material (local dirs, URLs, wikis)
- Seed `knowledge/taxonomy.yaml` with project-specific categories
- Optionally run `/research-intake` on provided URLs

### Step f: Review agent roles

- Present starter roles (lead-developer, research-engineer, safety-reviewer)
- Ask: add, remove, or customize any roles?
- Ask about project-specific roles needed
- Create/modify role files in `agents/roles/`

## Completion

- Remove `.needs-init` marker
- Print summary of what was configured
- Each step updates `.needs-init` to remove completed steps from `steps_remaining`
- Wizard can be re-entered (if steps remain) or re-triggered manually

## Gotchas

- The wizard is engine-neutral methodology; session-start detection is engine-specific
- `.needs-init` JSON format is the interface contract — each engine implements detection
- Start all 6 steps in sequence; user can skip steps (they get removed from remaining)
- If wizard is interrupted, remaining steps persist in `.needs-init` for next session
