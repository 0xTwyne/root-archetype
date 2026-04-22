# Handoff 5: Hook Consolidation + Settings

**Status**: completed
**Created**: 2026-04-09
**Priority**: 5 (can run in parallel with Handoffs 2-4 after Handoff 1)
**Estimated scope**: move/merge ~13 hooks → single directory, rewrite settings.json

---

## Context

Hooks are currently split across two directories:
- `scripts/hooks/` — 6 safety hooks (filesystem, secrets, test safety, schema, reference, skill log)
- `.claude/hooks/` — 7 lifecycle/policy hooks (session-start, session-end, pre-edit-guard, post-edit-check, post-tool-use-audit, correction-detection, subagent-start) + `lib/` (hook-utils.sh, session-counters.sh, secret-patterns.txt)

This split is confusing. Consolidate ALL hooks into `scripts/hooks/` and update `.claude/settings.json` to point there.

---

## Prerequisites

- Handoff 1 complete (non-core components removed)

---

## Tasks

### A. Move `.claude/hooks/*` → `scripts/hooks/`

| Source | Destination | Notes |
|--------|-------------|-------|
| `.claude/hooks/session-start.sh` | `scripts/hooks/session-start.sh` | Default ON |
| `.claude/hooks/session-end.sh` | `scripts/hooks/session-end.sh` | Default ON |
| `.claude/hooks/post-tool-use-audit.sh` | `scripts/hooks/post-tool-use-audit.sh` | Default ON |
| `.claude/hooks/pre-edit-guard.sh` | `scripts/hooks/pre-edit-guard.sh` | Optional |
| `.claude/hooks/post-edit-check.sh` | `scripts/hooks/post-edit-check.sh` | Optional |
| `.claude/hooks/correction-detection.sh` | `scripts/hooks/correction-detection.sh` | Optional |
| `.claude/hooks/subagent-start.sh` | `scripts/hooks/subagent-start.sh` | Optional |
| `.claude/hooks/lib/` | `scripts/hooks/lib/` | Shared utilities |

After moving, update any `source` or path references within the moved scripts that reference `.claude/hooks/lib/` → `scripts/hooks/lib/`.

### B. Review and deduplicate

Check for overlap between the two sets:
- Both directories may have audit/logging hooks — merge into single implementation
- `skill_usage_log.sh` in scripts/hooks/ may overlap with `post-tool-use-audit.sh` from .claude/hooks/ — evaluate and merge if redundant

### C. Delete `scripts/hooks/agents_reference_guard.sh`

This hook validates agent references against a registry that may not exist in the new structure. Evaluate:
- If it validates `agents/roles/*.md` references → keep but update paths
- If it validates swarm/dependency-map references → delete

### D. Rewrite `.claude/settings.json`

New settings.json with ALL paths pointing to `scripts/hooks/`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/hooks/session-start.sh",
            "timeout": 15000
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/hooks/session-end.sh",
            "timeout": 15000
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Glob|Grep|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/hooks/check_secrets_read.sh",
            "timeout": 5000
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/hooks/check_filesystem_path.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/hooks/post-tool-use-audit.sh",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

**Key changes from current**:
- Removed `check_test_safety.sh` from default PreToolUse (optional, not wired by default)
- Removed `pre-commit-hook.sh` from Bash matcher (safe-commit skill wires its own hooks)
- Removed `skill_usage_log.sh` from Skill matcher (merged into post-tool-use-audit or removed)
- Removed `agents_schema_guard.sh` from Write|Edit matcher (optional, not wired by default)
- Removed `pre-edit-guard.sh` from Write|Edit matcher (optional)
- Removed `post-edit-check.sh` from PostToolUse (optional)
- Removed `correction-detection.sh` from UserPromptSubmit (optional)
- Removed `subagent-start.sh` from SubagentStart (optional)
- ALL paths now use `scripts/hooks/` prefix

### E. Delete `.claude/hooks/` directory

After all hooks moved and settings.json updated, delete `.claude/hooks/` entirely.

### F. Write `scripts/hooks/README.md`

Document all hooks with their status:

```markdown
# Hooks

All hooks live in this directory. Engine settings wire them.

## Default (always-on)

| Hook | Event | Purpose |
|------|-------|---------|
| session-start.sh | SessionStart | Session init, .needs-init detection, stale wiki check |
| session-end.sh | SessionEnd | Progress report, session summary |
| check_secrets_read.sh | PreToolUse (Read/Glob/Grep/Bash) | Block access to protected paths |
| check_filesystem_path.sh | PreToolUse (Write/Edit) | Prevent writes outside project |
| post-tool-use-audit.sh | PostToolUse | Audit trail logging |

## Optional (shipped but not wired by default)

| Hook | Event | Purpose | Enable via |
|------|-------|---------|-----------|
| check_test_safety.sh | PreToolUse (Bash) | Bounded test parallelism | Init wizard step d |
| agents_schema_guard.sh | PreToolUse (Write/Edit) | 6-section schema enforcement | Init wizard step d |
| pre-edit-guard.sh | PreToolUse (Write/Edit) | Edit policy enforcement | Init wizard step d |
| post-edit-check.sh | PostToolUse (Edit/Write) | Post-edit validation | Init wizard step d |
| correction-detection.sh | UserPromptSubmit | User correction learning | Init wizard step d |
| subagent-start.sh | SubagentStart | Subagent policy injection | Init wizard step d |

## Shared Utilities

`lib/` contains shared functions used by multiple hooks:
- `hook-utils.sh` — Common hook helper functions
- `session-counters.sh` — Session statistics tracking
- `secret-patterns.txt` — Secret detection patterns
```

### G. Update `.claude/settings.local.json` template

Ensure it references only `scripts/hooks/` paths. Current template lives in `_templates/` (deleted in Handoff 1), so recreate inline guidance in `local/README.md` or `scripts/hooks/README.md`.

---

## Acceptance Criteria

1. `.claude/hooks/` directory does not exist
2. All hooks live in `scripts/hooks/` (including lib/)
3. `.claude/settings.json` references only `scripts/hooks/` paths
4. Default wiring: 5 hooks (session-start, session-end, secrets, filesystem, audit)
5. Optional hooks exist in `scripts/hooks/` but are not wired in default settings.json
6. `scripts/hooks/README.md` documents all hooks with default/optional status
7. No broken path references (grep for `.claude/hooks` in all shell scripts — should be 0)

---

## Risks

- **Hook path references**: Scripts in `.claude/hooks/` may `source .claude/hooks/lib/hook-utils.sh` — these internal references must be updated to `scripts/hooks/lib/`.
- **settings.local.json**: Users who have customized their local settings will need to update hook paths. Document this in README.
- **Safe-commit skill**: Currently wires `pre-commit-hook.sh` via settings.json Bash matcher. After consolidation, the safe-commit skill should wire its own hook or the user enables it via init wizard. The skill's internal scripts need path updates.
