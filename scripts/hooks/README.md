# Hooks

All hooks live in `scripts/hooks/`. Claude Code wiring in `.claude/settings.json`
points to paths here.

## Default Hooks (wired in settings.json)

| Hook | Event | Description |
|------|-------|-------------|
| `session-start.sh` | SessionStart | Resolve user, create branch, per-user dirs, load facts |
| `session-end.sh` | SessionEnd | Write progress, push logs, commit session work |
| `check_secrets_read.sh` | PreToolUse (Read/Glob/Grep/Bash) | Block reads of protected paths |
| `check_filesystem_path.sh` | PreToolUse (Write/Edit) | Prevent writes outside project |
| `post-tool-use-audit.sh` | PostToolUse | Append-only audit trail logging |

## Optional Hooks (shipped but not wired by default)

| Hook | Event | Description |
|------|-------|-------------|
| `pre-edit-guard.sh` | PreToolUse (Write/Edit) | Secret scan + log isolation + config tamper-proofing |
| `post-edit-check.sh` | PostToolUse (Edit/Write) | Post-edit validation for child repos |
| `correction-detection.sh` | UserPromptSubmit | Detect user corrections for learning |
| `subagent-start.sh` | SubagentStart | Inject context into subagent sessions |
| `check_test_safety.sh` | PreToolUse (Bash) | Bounded test parallelism |
| `agents_schema_guard.sh` | PreToolUse (Write/Edit) | 6-section agent schema enforcement |
| `agents_reference_guard.sh` | PreToolUse (Write/Edit) | Agent reference validation |
| `skill_usage_log.sh` | PreToolUse (Skill) | Skill usage logging |

## Shared Library

`scripts/hooks/lib/` contains shared utilities:

- `hook-utils.sh` — Common functions (hook_silent, hook_block, hook_warn, hook_load_identity, etc.)
- `log-repo.sh` — Log repo resolution (hook_resolve_log_repo, hook_is_split_mode, hook_ensure_log_dirs)
- `session-counters.sh` — Per-session dedup counters
- `secret-patterns.txt` — Shared secret detection patterns (tab-separated: label, regex, replacement)

### Log Repo Resolution

All hooks automatically gain access to `$LOG_REPO_DIR` by sourcing `hook-utils.sh`,
which sources `log-repo.sh`. The resolution flow:

1. Check `$ARCHETYPE_LOG_REPO` env var (explicit override)
2. Read `.archetype-manifest.json` → `log_repo_name` → `repos/<name>` directory
3. Fallback to `$PROJECT_DIR` (pre-init or broken path)

Use `hook_is_split_mode` to check if the log repo is separate from the root repo.
Use `hook_ensure_log_dirs "$SESSION_USER"` to create per-user directories in the log repo.

## Enabling Optional Hooks

Add entries to `.claude/settings.json` following the patterns in the default hooks.
The init wizard (`--guided` mode) provides an interactive hook selection menu.

**Important:** All hook commands must use the `${CLAUDE_PROJECT_DIR:-.}/` prefix
so paths resolve correctly regardless of working directory:

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/hooks/pre-edit-guard.sh\"",
      "timeout": 5000
    }
  ]
}
```

Do **not** use bare relative paths like `bash scripts/hooks/pre-edit-guard.sh` —
these fail when Claude Code's working directory is not the project root
(e.g., during worktree operations or subagent execution).
