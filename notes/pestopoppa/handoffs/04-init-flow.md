# Handoff 4: Init Flow

**Status**: active
**Created**: 2026-04-09
**Priority**: 4 (depends on Handoffs 1-3 for final structure)
**Estimated scope**: 1 rewrite (init-project.sh), 1 new skill, hook update

---

## Context

`init-project.sh` is currently 419 lines and scaffolds the old structure (including swarm, gitnexus, nightshift). It needs a rewrite for the new lean structure. The guided mode is new: it drops a `.needs-init` marker that triggers an interactive wizard on first agent session.

---

## Prerequisites

- Handoff 1 complete (removed components gone)
- Handoff 2 complete (AGENT.md exists, skill structure settled)
- Handoff 3 complete (knowledge/ structure exists)

---

## Tasks

### A. Rewrite `init-project.sh` (~180 lines)

**Quick mode** (default):
```bash
./init-project.sh <project-name> <target-path>
```

1. Copy core structure to `<target-path>/<project-name>/`
2. Replace all `{{PROJECT_NAME}}` placeholders with `<project-name>`
3. Replace `{{PROJECT_ROOT}}` with the absolute target path
4. Initialize git repo (if not already one)
5. Print summary of what was created + next steps
6. Complete in <5 seconds, no interactive prompts

**Guided mode**:
```bash
./init-project.sh <project-name> <target-path> --guided
```

1. Do everything quick mode does
2. Drop `.needs-init` marker file:

```json
{
  "project_name": "<project-name>",
  "created": "2026-04-09T...",
  "init_mode": "guided",
  "steps_remaining": ["repos", "child-agents", "maintainer", "hooks", "knowledge", "roles"]
}
```

3. Print: "Guided mode: start a Claude or Codex session to complete setup."

**What gets copied** (the template files):

```
AGENT.md
CLAUDE.md
CODEX.md
MAINTAINERS.json
README.md
agents/               (shared/, roles/, skills/, README.md)
scripts/hooks/        (all hooks)
scripts/utils/        (agent_log.sh, session_init.sh, health_check.sh)
scripts/repos/        (register-repo.sh, scan-agents.sh, sync-repos.sh)
scripts/validate/     (all validators)
secrets/              (.gitkeep, .secretpaths)
logs/                 (empty structure)
notes/                (README.md)
knowledge/            (taxonomy.yaml template, research/intake_index.yaml)
local/                (.gitkeep, README.md)
repos/                (.gitkeep)
.claude/              (settings.json, skills/ wrappers)
.devcontainer/        (devcontainer.json)
.gitignore
```

**What does NOT get copied**:
- No swarm, nightshift, upstream, gitnexus, templates
- No progress data, handoff data, notes data (empty structure only)
- No `.claude/settings.local.json` (per-machine, gitignored)

### B. Create `agents/skills/init-wizard/SKILL.md`

The init wizard is triggered when an agent session detects `.needs-init`. It walks through interactive setup steps:

```markdown
---
name: init-wizard
description: Guided project initialization wizard
---

# Init Wizard

## Trigger
`.needs-init` file exists in project root (detected by session-start hook)

## Steps

### Step a: Register child repos
- Ask user for child repo paths and purposes
- Run `scripts/repos/register-repo.sh` for each
- Update `AGENT.md` repository map

### Step b: Child repo agent scaffolding
- For each registered child repo WITHOUT an AGENT.md:
  - Scan: file structure, languages, key patterns
  - Generate draft AGENT.md for the child repo
  - Present to user for review/edit
  - On approval: write to child repo
- For repos WITH existing agent files: note and skip

### Step c: Set maintainer(s)
- Ask for maintainer email(s)
- Write `MAINTAINERS.json`
- Optionally set per-child-repo maintainers

### Step d: Choose hooks
- Present menu of available hooks:
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
- Wire selected hooks into `.claude/settings.json`

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
- Each step updates `.needs-init` to remove completed steps
- Wizard can be re-entered (if steps remain) or re-triggered manually
```

Also create thin Claude wrapper at `.claude/skills/init-wizard/SKILL.md`.

### C. Update session-start hook for `.needs-init` detection

Add to `scripts/hooks/session-start.sh`:

```bash
# Guided init detection
if [ -f ".needs-init" ]; then
  echo "🔧 This project needs initial setup. The init wizard will guide you."
  echo "NEEDS_INIT=true"
fi
```

The agent session reads this output and triggers the init-wizard skill.

### D. Update `scripts/repos/register-repo.sh`

Adapt for new structure:
- Register repos in `repos/` directory (symlinks or metadata files)
- Update `AGENT.md` repository map table
- Do NOT reference `.claude/dependency-map.json` (deleted in Handoff 1)
- Scan child repo for existing agent files and report status

---

## Acceptance Criteria

1. `init-project.sh` is ≤200 lines
2. Quick mode: `./init-project.sh test /tmp/test` creates working structure in <5s
3. Guided mode: `./init-project.sh test /tmp/test --guided` creates structure + `.needs-init`
4. `.needs-init` marker has correct JSON format with all 6 steps
5. `agents/skills/init-wizard/SKILL.md` documents all 6 wizard steps
6. Session-start hook detects `.needs-init` and signals the agent
7. `register-repo.sh` works with new directory layout
8. Generated project has NO references to swarm, gitnexus, nightshift, upstream

---

## Risks

- **Init wizard as a skill**: The wizard is complex (6 steps, interactive). Skills work best as single-action methodology. Consider whether each step should be a separate sub-skill or one monolithic skill with sections. Start monolithic, split later if needed.
- **Cross-engine wizard**: The wizard methodology is engine-neutral, but the session-start hook detection is Claude-specific. Codex and other engines need equivalent detection. Document the interface contract (`.needs-init` JSON format) so each engine can implement detection.
