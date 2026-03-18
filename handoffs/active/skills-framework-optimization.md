# Skills Framework Optimization

**Status**: active
**Created**: 2026-03-18
**Last audited**: 2026-03-18
**Origin**: Cross-reference analysis of Anthropic internal skills practices (Thariq Shihipar, MTS Claude Code, March 2026 blog) and official "Complete Guide to Building Skills for Claude" (Anthropic, 29-page PDF) against epyc-root governance instance
**Scope**: root-archetype — all future root project instances

---

## Context

Anthropic's Claude Code team has published definitive guidance on skills engineering, distilled from hundreds of internal production skills. This handoff captures the delta between those best practices and root-archetype's current skills infrastructure, with concrete remediation steps.

**Source documents**:
1. "Lessons from Building Claude Code: How We Use Skills" — Thariq Shihipar (Anthropic MTS, Claude Code team), LinkedIn, 2026-03-18
2. "The Complete Guide to Building Skills for Claude" — Anthropic official PDF, 29 pages, 6 chapters

---

## Current State (root-archetype)

- **2 skills** (swarm, upstream) — both lack YAML frontmatter entirely
- **2 commands** (swarm.md, upstream.md)
- **11 hooks** — 7 in `.claude/hooks/` (session-start, session-end, pre-edit-guard, post-edit-check, post-tool-use-audit, correction-detection, subagent-start) + 4 in `scripts/hooks/` (check_filesystem_path, agents_schema_guard, agents_reference_guard, check_test_safety) — all always-on globals, none skill-scoped
- **Hook lib/ already exists** — `.claude/hooks/lib/` contains `hook-utils.sh`, `session-counters.sh`, `secret-patterns.txt` (twyne-root pattern already adopted)
- **No progressive disclosure** — no references/, scripts/, or assets/ subdirectories in skill folders
- **No gotchas sections** in any skill
- **No skill measurement** infrastructure
- **No trigger test suites**
- **No skill templates** for instance authors to create new skills
- **`simplify` skill exists externally** — listed in system prompt as available skill but no file in `.claude/skills/`. Likely installed via user-level config or npx package. Needs decision: create archetype-owned version or declare external dependency.
- **No `_templates/` directory** exists yet
- **No `init-project.sh`** exists yet — referenced in acceptance criteria but out of scope for this handoff
- **`docs/guides/` directory exists** but is empty

---

## Key Principles from Anthropic (to encode in archetype)

### P1. Three-Level Progressive Disclosure

Skills use a three-level system to minimize token usage while maintaining expertise:

- **Level 1 (YAML frontmatter)**: Always loaded into system prompt. Must contain `name` (kebab-case) and `description` (trigger specification, not summary). This is how Claude decides whether to load the skill.
- **Level 2 (SKILL.md body)**: Loaded only when Claude thinks the skill is relevant. Contains full instructions, gotchas, workflow.
- **Level 3 (Linked files)**: Additional files in references/, scripts/, assets/ that Claude discovers and reads on demand.

### P2. Description Field = Trigger Specification

The description is NOT a summary — it's what Claude scans to decide "is there a skill for this request?" Formula:

```
[What it does] + [When to use it] + [Key capabilities]
```

Good: `"Manages cross-repo handoff lifecycle including creation, status updates, and archival. Use when user mentions 'handoff', 'work item', 'cross-repo task', or asks to track work across repositories."`

Bad: `"Helps with handoffs."`

### P3. Gotchas Section = Highest-Signal Content

Every skill should have a `## Gotchas` section listing common failure points Claude hits. This section grows over time as edge cases are discovered. It is the single most valuable part of a skill after the first week of use.

### P4. Don't State the Obvious / Don't Railroad

- Skip knowledge Claude already has (general coding, common CLI tools)
- Focus on information that pushes Claude off its default behavior
- Give intent + guardrails, not rigid step-by-step scripts
- Bad: `"Step 1: Run git log. Step 2: Run git cherry-pick. Step 3: ..."`
- Good: `"Cherry-pick the commit onto a clean branch. Resolve conflicts preserving intent. If it can't land cleanly, explain why."`

### P5. Skills Are Folders, Not Files

Use the filesystem for context engineering:
- `scripts/` — executable code Claude can run (validators, data fetchers)
- `references/` — detailed docs Claude reads on demand (API patterns, schema specs)
- `assets/` — templates, example outputs Claude copies and adapts

### P6. Data Persistence Across Runs

Skills can store append-only data for cross-session memory:
- Log files (e.g., `standups.log` with every prior standup)
- Use `$(CLAUDE_PLUGIN_DATA)` for upgrade-safe storage
- Enables "what changed since yesterday?" patterns

> **Implementation note**: `CLAUDE_PLUGIN_DATA` availability in hook execution context needs verification. Fallback: use a project-local path like `logs/skills/` if the env var is unset.

### P7. On-Demand Hooks

Skills can register hooks that activate only when the skill is invoked:
- `/careful` — blocks destructive operations (rm -rf, force-push, DROP TABLE)
- `/freeze` — blocks edits outside a specific directory
- Use for situational guardrails that would be too aggressive always-on

### P8. Skill Composition

Skills can reference other skills by name. Claude will invoke them if installed:
- Enables modular, composable workflows
- Governance skill can compose agent-validation + CLAUDE.md-accounting

### P9. Measurement

Add a PreToolUse hook that logs skill invocations to detect:
- **Undertriggering**: skill doesn't load when it should → add keywords to description
- **Overtriggering**: skill loads for irrelevant queries → add negative triggers, be more specific

---

## Anthropic's 9 Skill Categories

Map each category to governance root applicability:

| # | Category | Root Applicable? | Archetype Skill |
|---|----------|:---:|---|
| 1 | Library & API Reference | Yes | `repo-api` — gotchas for child repo CLIs, build systems, key scripts |
| 2 | Product Verification | Yes | `stack-verify` — smoke-test infrastructure, assert health endpoints |
| 3 | Data Fetching & Analysis | Situational | Instance-specific (benchmarks, metrics) |
| 4 | Business Process & Team Automation | Yes | `new-handoff` — templated handoff creation with lifecycle automation |
| 5 | Code Scaffolding & Templates | Yes | `new-skill` — scaffold a new skill with correct structure |
| 6 | Code Quality & Review | Yes | `simplify` — adversarial review of changed code |
| 7 | CI/CD & Deployment | Yes | `safe-commit` — commit with guardrails, hook for production branches |
| 8 | Runbooks | Yes | `debug-runbook` — symptom→diagnostic chain templates |
| 9 | Infrastructure Ops | Situational | Instance-specific (model lifecycle, server management) |

---

## Anthropic's 5 Workflow Patterns

| Pattern | Use When | Archetype Relevance |
|---------|----------|-------------------|
| Sequential Orchestration | Multi-step processes in specific order | Handoff lifecycle, upstream pipeline |
| Multi-MCP Coordination | Workflows spanning multiple services | Cross-repo operations |
| Iterative Refinement | Output quality improves with iteration | Code review, document generation |
| Context-Aware Tool Selection | Same outcome, different tools by context | Repo-specific validation dispatch |
| Domain-Specific Intelligence | Specialized knowledge beyond tool access | Governance policy, agent schema rules |

---

## Remediation Plan

### Phase 1: Structural Foundation (apply to archetype itself)

#### 1.1 Add YAML frontmatter to existing skills

**swarm/SKILL.md** — add:
```yaml
---
name: swarm
description: Launch and manage multi-agent swarm coordination for parallel work. Use when user mentions "swarm", "parallel agents", "workers", "work queue", or asks to coordinate multiple agents on a task.
---
```

**upstream/SKILL.md** — add:
```yaml
---
name: upstream
description: Extract governance improvements from this project instance and submit as PR to root-archetype. Use when user says "upstream", "contribute back", "archetype PR", or wants to propose changes to the governance template.
---
```

#### 1.2 Add Gotchas sections to existing skills

**swarm** gotchas:
- SQLite coordinator.db must not be accessed by multiple processes simultaneously
- Worker count should not exceed available CPU threads / 2 (each worker needs inference capacity)
- Stale locks from crashed workers require manual `coordinator.release_lock()` cleanup

**upstream** gotchas:
- `.archetype-manifest.json` must exist before upstream works — run `retroactive-manifest.sh` first
- Reverse-templating is fragile: unusual project names containing regex metacharacters will fail silently
- Always `--dry-run` first to verify contamination check catches all project-specific references

#### 1.3 Add progressive disclosure structure

Create directory scaffolding with `.gitkeep` files. Content authoring for reference docs is a separate effort tracked below.

```
.claude/skills/swarm/
├── SKILL.md
├── references/
│   └── coordinator-api.md      # SQLite schema, Python client API
└── scripts/
    └── swarm_status.sh         # Quick status check script

.claude/skills/upstream/
├── SKILL.md
├── references/
│   └── manifest-spec.md        # .archetype-manifest.json schema
└── scripts/
    └── upstream_dry_run.sh     # Wrapper for --dry-run mode
```

> **Content authoring required**: `coordinator-api.md` and `manifest-spec.md` are net-new reference documents that need to be written from existing source code. Estimate: extract from `swarm/coordinator.py` schema and `scripts/upstream/` respectively. Initial pass can be auto-generated, then refined.

### Phase 2: New Archetype Skills

#### 2.1 `new-skill` (Scaffolding) — PRIORITY

A meta-skill that scaffolds new skills with correct structure. This is the force multiplier — every instance author uses this to create instance-specific skills correctly.

```yaml
---
name: new-skill
description: Scaffold a new Claude Code skill with correct folder structure, YAML frontmatter, gotchas section, and progressive disclosure. Use when user says "create a skill", "new skill", "scaffold skill", or "add a skill".
---
```

Contents:
- Template SKILL.md with all required sections
- Validation script checking frontmatter, description formula, folder structure
- Reference doc with the description formula and good/bad examples
- Gotchas from Anthropic's guide (naming rules, description anti-patterns)

#### 2.2 `find-skills` (Meta-Discovery) — FROM TWYNE-ROOT

```yaml
---
name: find-skills
description: Discover and install agent skills from the open ecosystem. Use when user asks "how do I do X", "find a skill for X", "is there a skill that can...", or expresses interest in extending capabilities. Do NOT use when user asks about already-installed skills.
---
```

Contents:
- Wraps `npx skills find [query]` / `npx skills add <package>`
- Category-aware search (web dev, testing, devops, docs, code quality, design, productivity)
- Handles "no results" gracefully (offer direct help + `npx skills init`)
- Reference: twyne-root's `find-skills` skill

> **External dependency**: Requires `skills` npm package (`npx skills`). Skill must degrade gracefully if not installed — detect with `command -v npx` and offer install instructions. Consider whether this belongs in archetype (all instances) vs instance-specific install.

#### 2.3 `new-handoff` (Business Process)

```yaml
---
name: new-handoff
description: Create a structured handoff document for cross-repo work tracking. Use when user says "new handoff", "create handoff", "track work item", or needs to document work for another session/agent to pick up.
---
```

Contents:
- Handoff template with required sections (Status, Context, Current State, Remediation Plan, Acceptance Criteria)
- Script to check for duplicate handoff titles
- Reference doc with handoff lifecycle rules

#### 2.4 `safe-commit` (CI/CD)

```yaml
---
name: safe-commit
description: Commit changes with governance guardrails including pre-commit validation, sensitive file detection, and hook compliance. Use when user says "commit", "save changes", or "push". Do NOT use for general git questions.
---
```

On-demand hooks:
- Block commits containing credentials patterns (.env, API keys, tokens)
- Warn on commits to main/master without PR
- Run governance validators before commit

> **Overlap warning**: Existing infrastructure already provides partial coverage — `pre-edit-guard.sh` guards filesystem paths, `secret-patterns.txt` detects credentials, `check_filesystem_path.sh` validates paths. This skill must **compose** with existing hooks, not duplicate them. Specifically: the skill should orchestrate running validators + generating a clean commit message, while credential detection stays in the existing hook layer. Risk of overtriggering on normal `/commit` usage — consider requiring explicit invocation only (no auto-trigger on "commit").

#### 2.5 `simplify` (Code Quality)

```yaml
---
name: simplify
description: Review changed code for reuse opportunities, quality issues, and unnecessary complexity. Use when user says "review", "simplify", "clean up", or after completing a significant code change.
---
```

> **Pre-existing external skill**: `simplify` already appears in the session system prompt as an available skill (likely installed via user-level config or npx package). Decision needed: (a) create an archetype-owned version that supersedes the external one, (b) declare the external version as the standard and document it, or (c) skip this and let instances choose. Recommendation: option (a) — an archetype-owned `simplify` ensures consistent behavior across all instances and can be governance-aware.

### Phase 3: Skill Infrastructure

#### 3.1 Skill validator (`scripts/validate/validate_skills.py`)

Checks all skills in `.claude/skills/` for:
- [ ] SKILL.md exists (exact case)
- [ ] Valid YAML frontmatter with `---` delimiters
- [ ] `name` field present, kebab-case, matches folder name
- [ ] `description` field present, under 1024 chars, no XML angle brackets
- [ ] Description contains trigger phrases (heuristic: contains "Use when" or "Trigger")
- [ ] If `allowed-tools` present, validate format matches `Tool(pattern)` syntax
- [ ] Gotchas section exists (`## Gotchas` or `## Common Issues`)
- [ ] No README.md inside skill folder
- [ ] SKILL.md under 5000 words (warn if over)

Wire into pre-commit validation alongside `validate_agents_structure.py`.

#### 3.2 Skill measurement hook

Add to `scripts/hooks/skill_usage_log.sh`:
- Triggered on PreToolUse for Skill tool
- Appends to skill invocations log
- Format: `TIMESTAMP | SKILL_NAME | TRIGGER_QUERY_PREVIEW`
- Analysis script: `scripts/utils/skill_usage_analyze.sh --summary`

> **Storage path**: Use `CLAUDE_PLUGIN_DATA` env var if available, otherwise fall back to `logs/skills/invocations.log` (project-local). The hook must handle the fallback gracefully:
> ```bash
> LOG_DIR="${CLAUDE_PLUGIN_DATA:-logs/skills}"
> mkdir -p "$LOG_DIR"
> ```
> Wire into settings.json as a new PreToolUse hook with `"matcher": "Skill"`.

#### 3.3 Skill template directory

Create `_templates/skill/` containing:
```
_templates/skill/
├── SKILL.md.template          # Frontmatter + sections skeleton
├── references/.gitkeep
├── scripts/.gitkeep
└── assets/.gitkeep
```

Used by `new-skill` skill and by `init-project.sh` for fresh instances.

#### 3.4 Trigger test framework

Each skill can optionally include `tests/triggers.md`:
```markdown
## Should Trigger
- "Help me create a new handoff for the auth refactor"
- "I need to track this work for the next session"
- "Create a cross-repo task"

## Should NOT Trigger
- "What is a handoff in basketball?"
- "Hand off the phone to someone else"
- "Create a new file"
```

> **Scope clarification**: This is a **documentation artifact for human review**, not an automated test suite. There is no programmatic way to test "would Claude trigger skill X for query Y?" without running an actual Claude session. The value is: (1) forces skill authors to think about trigger boundaries, (2) provides regression cases when refining descriptions, (3) can be manually tested during skill development. Do not over-invest in automation here.

### Phase 4: Documentation

#### 4.1 Skills engineering guide

Create `docs/guides/skills-engineering.md` covering:
- The three-level progressive disclosure model
- Description formula with good/bad examples
- The 9 category taxonomy
- The 5 workflow patterns
- Gotchas growth protocol (add a line each time Claude hits an edge case)
- On-demand hooks pattern
- Skill composition pattern
- Measurement and iteration

This becomes the reference doc for anyone creating skills in any root-archetype instance.

---

## Acceptance Criteria

### Must-have (gates handoff completion)

- [x] All existing archetype skills have valid YAML frontmatter (Phase 1.1)
- [x] All existing archetype skills have Gotchas sections (Phase 1.2)
- [x] Progressive disclosure directories exist for all skills (Phase 1.3)
- [x] Skill validator script exists and passes on all skills (Phase 3.1)
- [x] `new-skill` meta-skill exists and produces correct scaffolding (Phase 2.1)
- [x] Skill template directory exists in `_templates/skill/` (Phase 3.3)

### Should-have (high value, complete if time allows)

- [x] `new-handoff` skill exists with template (Phase 2.3)
- [x] Skill measurement hook is wired and logging (Phase 3.2)
- [x] Skills engineering guide exists in `docs/guides/` (Phase 4.1)
- [x] Reference docs authored for swarm and upstream (Phase 1.3 content)

### Nice-to-have (can be separate follow-up handoffs)

- [ ] `find-skills` meta-discovery skill (Phase 2.2 — external dependency)
- [ ] `safe-commit` skill (Phase 2.4 — needs deconfliction with existing hooks)
- [ ] `simplify` archetype-owned version (Phase 2.5 — needs decision on external vs owned)
- [ ] Trigger test examples exist for all skills (Phase 3.4 — documentation artifact)
- [ ] At least one on-demand hook pattern is demonstrated (Phase 2.4)

### Out of scope (tracked separately)

- [ ] `init-project.sh` propagates skill templates to new instances — **no `init-project.sh` exists yet**; this is a project initialization feature, not a skills optimization task. Track as a separate handoff.

---

## Implementation Order

Recommended sequence based on dependency analysis and value delivery:

| Step | Phase | What | Why first | Depends on |
|------|-------|------|-----------|------------|
| 1 | 1.1 + 1.2 | YAML frontmatter + gotchas on existing skills | Quick wins, immediate compliance | — |
| 2 | 3.1 | Skill validator | Gates all subsequent work — validates as we go | — |
| 3 | 1.3 | Progressive disclosure directories | Structural scaffolding, mostly mkdir | Step 1 |
| 4 | 3.3 | Skill template directory (`_templates/skill/`) | Needed by new-skill | — |
| 5 | 2.1 | `new-skill` meta-skill | Force multiplier — used to create all subsequent skills | Steps 2, 4 |
| 6 | 3.2 | Measurement hook | Start collecting data early | — |
| 7 | 2.3 | `new-handoff` skill | High-value business process automation | Step 5 |
| 8 | 1.3 (content) | Reference docs for swarm + upstream | Completes progressive disclosure | Step 3 |
| 9 | 4.1 | Skills engineering guide | Documents everything built so far | Steps 1-7 |
| 10 | 2.2 | `find-skills` | External dependency, lower urgency | — |
| 11 | 2.4 | `safe-commit` | Needs deconfliction design with existing hooks | — |
| 12 | 2.5 | `simplify` | Needs decision on external vs archetype-owned | — |
| 13 | 3.4 | Trigger test docs | Documentation artifact, lowest priority | Steps 1, 5, 7 |

---

## Learnings from twyne-root Audit (2026-03-18)

Full audit: `twyne-root/notes/pestopoppa/skills-audit-anthropic-best-practices.md`

twyne-root (10 skills, 24 hooks) is significantly more mature than root-archetype. These patterns should be encoded as archetype standards:

### Exemplar Patterns to Encode

1. **`agent-browser` as reference architecture for complex skills**
   - YAML frontmatter with `allowed-tools: Bash(agent-browser:*)` — skill-scoped tool permissions
   - Progressive disclosure: SKILL.md → `references/` (6 docs) → `templates/` (3 scripts)
   - Explicit Gotchas section ("Ref Lifecycle") for the #1 failure mode
   - Trigger description with exhaustive keyword list

2. **Library/index pattern for external best-practice skills**
   - SKILL.md serves as index pointing to `rules/` subdirectory
   - `remotion-best-practices`: 27 rule files; `vercel-react-best-practices`: 57 rule files
   - Claude loads index (Level 2), then reads specific rules on demand (Level 3)

3. **`find-skills` as mandatory archetype skill (meta-discovery)**
   - Triggers on intent: "how do I do X", "find a skill for X", "can you do X"
   - Wraps `npx skills find` / `npx skills add` from the skills.sh ecosystem
   - Handles "no results" gracefully (offers direct help + `npx skills init`)
   - **Action**: Add `find-skills` to Phase 2 new skills list

4. **`allowed-tools` frontmatter for skill-scoped tool permissions**
   - Only `agent-browser` uses it currently, but the pattern is powerful
   - Restricts which tools a skill can invoke (security boundary)
   - **Action**: Add `allowed-tools` validation to skill validator (Phase 3.1)

5. **Hook `lib/` pattern for shared utilities**
   - `hooks/lib/hook-utils.sh` — common functions across hooks
   - `hooks/lib/session-counters.sh` — session state tracking
   - `hooks/lib/secret-patterns.txt` — shared detection patterns
   - Prevents code duplication and behavioral drift between hooks

6. **Decision matrices in overlapping skills**
   - `colgrep` and `gitnexus` both include "When to Use What" tables
   - Disambiguates: ColGrep (semantic) vs GitNexus (structural) vs Grep (exact) vs Glob (filename)
   - **Rule**: Any archetype skill that overlaps with another MUST include a decision matrix

### twyne-root Gaps (avoid replicating in archetype)

- 6/10 skills lack explicit Gotchas sections
- 4/10 skills have terse descriptions without trigger phrases
- No skill validator script
- No skill measurement/telemetry
- No negative triggers in descriptions (overtriggering risk)
- No deprecation/lifecycle metadata

---

## Propagation Notes

Terminology clarification:
- **Upstream** = instance → archetype (contributing learnings back to the template)
- **Downstream** = archetype → instance (new instances inherit archetype changes)

When this handoff is complete in root-archetype:
1. Downstream propagation is automatic: any future root instance seeded from the archetype inherits the optimized framework
2. For existing instances (epyc-root, twyne-root): run `/upstream` from the instance to pull archetype improvements, or manually apply relevant changes
3. Epyc-root then applies instance-specific skills (debug-inference, model-lifecycle, benchmark, stack-verify) on top of the archetype base

---

## Source References

- Thariq Shihipar, "Lessons from Building Claude Code: How We Use Skills", LinkedIn, 2026-03-18
- Anthropic, "The Complete Guide to Building Skills for Claude", PDF, 29 pages (Chapters: Fundamentals, Planning & Design, Testing & Iteration, Distribution & Sharing, Patterns & Troubleshooting, Resources)
- Anthropic Skills GitHub: anthropics/skills
- Agent Skills open standard specification

---

## Audit Log

### 2026-03-18 — Pre-implementation audit

**Auditor**: Claude (session/0bc95bc9-596_2026-03-18)

**Findings applied to this document**:

1. **Fixed**: Hook count was "8" — actual count is 11 (7 in `.claude/hooks/` + 4 in `scripts/hooks/`). Updated Current State.
2. **Fixed**: Numbering gap in Phase 2 (jumped 2.2 → 2.4). Renumbered 2.3-2.5.
3. **Added**: Note that hook `lib/` pattern from twyne-root is already adopted in archetype.
4. **Added**: `simplify` external skill conflict — exists in system prompt but no archetype file. Decision needed.
5. **Added**: `safe-commit` overlap warning with existing hook infrastructure (pre-edit-guard, secret-patterns.txt).
6. **Added**: `find-skills` external dependency note — `npx skills` may not be installed.
7. **Added**: `CLAUDE_PLUGIN_DATA` env var verification note with fallback path.
8. **Added**: Phase 1.3 content authoring note — reference docs are net-new writing, not just mkdir.
9. **Added**: Phase 3.4 scope clarification — trigger tests are documentation artifacts, not automated suites.
10. **Fixed**: `init-project.sh` moved from acceptance criteria to out-of-scope — doesn't exist, separate concern.
11. **Added**: Tiered acceptance criteria (must-have / should-have / nice-to-have / out-of-scope).
12. **Added**: Implementation Order table with dependency analysis.
13. **Added**: `docs/guides/` exists but is empty (noted in Current State).

**Assessment**: Ready for implementation. No blocking issues. Start with Steps 1-5 (Phase 1.1 through Phase 2.1) as a single implementation pass.
