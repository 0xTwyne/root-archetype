# Hooks

All Claude Code hooks live here. Registered in `.claude/settings.json`.

## Hook Inventory

### Session Lifecycle (Default ON)

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start.sh` | SessionStart | Resolve user, create session branch, load facts cache |
| `session-end.sh` | SessionEnd | Push logs to main, commit session work, create PR |
| `subagent-start.sh` | SubagentStart | Inject repo context and budget visibility into subagents |

### Policy Guards (Default ON)

| Hook | Trigger | Matcher | Purpose |
|------|---------|---------|---------|
| `check_secrets_read.sh` | PreToolUse | Read\|Glob\|Grep\|Bash | Block read access to paths in `secrets/.secretpaths` |
| `check_filesystem_path.sh` | PreToolUse | Write\|Edit | Block writes outside allowed paths |
| `pre-edit-guard.sh` | PreToolUse | Write\|Edit | Secret scan in content, log isolation, config tamper-proofing |
| `check_test_safety.sh` | PreToolUse | Bash | Block unbounded pytest parallelism |

### Validation (Default ON)

| Hook | Trigger | Matcher | Purpose |
|------|---------|---------|---------|
| `agents_schema_guard.sh` | PreToolUse | Write\|Edit | Enforce 6-section schema in `agents/*.md` |
| `agents_reference_guard.sh` | PreToolUse | Write\|Edit | Validate local markdown references in governance files |

### Observability (Default ON)

| Hook | Trigger | Purpose |
|------|---------|---------|
| `post-tool-use-audit.sh` | PostToolUse | Track tool calls, file modifications, subagent count |
| `post-edit-check.sh` | PostToolUse (Edit\|Write) | Ripple detection + write-time linting for child repos |
| `skill_usage_log.sh` | PreToolUse (Skill) | Log skill invocations for usage analysis |
| `correction-detection.sh` | UserPromptSubmit | Detect user corrections, prompt facts/agent-file updates |

## Shared Library (`lib/`)

| File | Purpose |
|------|---------|
| `hook-utils.sh` | Shared functions: `hook_block`, `hook_warn`, `hook_silent`, `hook_fail_open`, `hook_load_identity`, `hook_dedup_check`, `hook_timed_dedup` |
| `session-counters.sh` | Session-scoped counters for threshold-based hook behavior |
| `secret-patterns.txt` | Tab-separated secret detection patterns (label, regex, replacement) |

## Adding a Hook

1. Create `scripts/hooks/my-hook.sh` (exit 0 = silent pass, exit 2 = block with message)
2. Source `lib/hook-utils.sh` for standard utilities
3. Register in `.claude/settings.json` under the appropriate trigger
4. Use `hook_block` to block, `hook_warn` to warn, `hook_silent` to pass silently
