---
name: init-wizard
description: Guided project initialization wizard. Use when .needs-init exists in project root (detected by session-start hook). Do NOT use on already-initialized projects. Walks through 9 interactive setup steps.
---

# Init Wizard

Guided project initialization wizard for new archetype instances.

## Trigger

`.needs-init` file exists in project root (detected by session-start hook).

## Steps

### Step 1: Set project description

- Ask user for a short description of this governance workspace
- Write to `.archetype-manifest.json` → `template_values.description`
- Regenerate README if `scripts/utils/generate-readme.sh` is available

### Step 1.5: Log repo setup

- Show: "Log repo will be created at `repos/<project-name>-logs/` (default). Enter a custom path or press Enter to accept."
- Accept custom path or confirm default — always display the default explicitly
- Run `scripts/utils/init-log-repo.sh <path> <project-name>`
- Register via `scripts/repos/register-repo.sh <name>-logs <path> --purpose "Session logs, notes, handoffs, per-member wikis" --no-scaffold`
- Add `repos/<name>-logs/` to root `.gitignore`
- Update `.archetype-manifest.json` with `log_repo_name`

### Step 2: Register child repos

- Ask user for child repo paths and purposes
- Run `scripts/repos/register-repo.sh` for each
- Update `AGENT.md` repository map table

### Step 3: Detect maintainers

- For each registered child repo, run `scripts/utils/detect-maintainers.sh`
- Present discovered maintainers (from MAINTAINERS.json, CODEOWNERS, package.json, Cargo.toml, pyproject.toml, git log)
- Ask user to confirm or adjust
- Write to root `MAINTAINERS.json` → `repo_maintainers`

### Step 4: Child repo agent scaffolding

- For each registered child repo WITHOUT an AGENT.md:
  - Scan: file structure, languages, key patterns
  - Generate draft AGENT.md for the child repo
  - Present to user for review/edit
  - On approval: write to child repo
- For repos WITH existing agent files: note and skip

### Step 5: Set maintainer(s)

- Confirm global maintainer email(s) (pre-filled from auto-detection)
- Finalize `MAINTAINERS.json` with global + per-repo entries
- Optionally set protected paths in `secrets/.secretpaths`

### Step 6: Choose hooks

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

Wire selected hooks into `.claude/settings.json` (generated file — changes persist locally, not tracked in git).

Use the `${CLAUDE_PROJECT_DIR:-.}/` prefix for all hook command paths:
```json
"command": "bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/hooks/<hook-name>.sh\""
```
This ensures hooks resolve correctly regardless of working directory. See `scripts/hooks/README.md` for the full wiring pattern.

### Step 7: Knowledge setup

- Ask for existing docs/material (local dirs, URLs, wikis)
- Seed `knowledge/taxonomy.yaml` with project-specific categories
- Optionally run `/research-intake` on provided URLs

### Step 8: Review agent roles

- Present starter roles (lead-developer, research-engineer, safety-reviewer)
- Ask: add, remove, or customize any roles?
- Ask about project-specific roles needed
- Create/modify role files in `agents/roles/`

### Step 9: Finalize

- Regenerate README via `scripts/utils/generate-readme.sh`
- Run validators: `validate_agents_structure.py`, `validate_document_drift.py`, `validate_skills.py`
- Remove `.needs-init` marker
- Print summary of what was configured

## Completion

- Each step updates `.needs-init` to remove completed steps from `steps_remaining`
- Wizard can be re-entered (if steps remain) or re-triggered manually
- User can skip any step — it gets removed from remaining

## Gotchas

- The wizard is engine-neutral methodology; session-start detection is engine-specific
- `.needs-init` JSON format is the interface contract — each engine implements detection
- Steps are sequential but skippable; if interrupted, remaining steps persist for next session
- `detect-maintainers.sh` requires `jq` for full heuristic coverage; degrades gracefully without it
