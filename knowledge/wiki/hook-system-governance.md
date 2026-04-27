# Hook System & Governance Enforcement

**Category**: governance

Claude Code hook events, default vs optional hooks, and CWD-independent invocation.

## Summary

All hooks live in `scripts/hooks/` — single source of truth, no `.claude/hooks/` split. The hook system spans six Claude Code events: `SessionStart`, `SessionEnd`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SubagentStart`. Five hooks are wired by default (`session-start`, `session-end`, `check_secrets_read`, `check_filesystem_path`, `post-tool-use-audit`); six more ship in the same directory but are not wired by default — enable them via `init-wizard` or by editing `.claude/settings.json`.

Hook commands in `settings.json` use the `${CLAUDE_PROJECT_DIR:-.}/` prefix. This makes them resolve correctly from any working directory — including worktree operations and subagent execution contexts where Claude Code's CWD is not the project root. Bare relative paths silently fail in those contexts; the prefix is mandatory.

`scripts/hooks/lib/` holds shared utilities: `hook-utils.sh` (block / warn / silent helpers, identity loading, tool resolution), `log-repo.sh` (log repo path resolution), `session-counters.sh` (per-session dedup state), `secret-patterns.txt` (regex library). All hooks follow a fail-open pattern: if a prerequisite is missing they exit 0 so adopting the archetype never breaks new instances.

## Key Points

- All hooks live in `scripts/hooks/` (no `.claude/hooks/` split)
- 5 default-on hooks (session start/end, secrets-read check, filesystem path check, post-tool audit) + 6 optional
- `${CLAUDE_PROJECT_DIR:-.}/` prefix on hook commands in `settings.json` — mandatory for CWD independence
- Fail-open pattern: hooks check prerequisites and exit 0 if missing
- `lib/` provides shared utilities so individual hooks stay small
- Hook events scoped to phases: `PreToolUse` for read/write gates, `PostToolUse` for audit, lifecycle hooks for boundaries
- See [`scripts/hooks/README.md`](../../scripts/hooks/README.md) for the full per-hook table with enable instructions

## See Also

- [`scripts/hooks/README.md`](../../scripts/hooks/README.md) — full per-hook documentation
- [`scripts/hooks/lib/hook-utils.sh`](../../scripts/hooks/lib/hook-utils.sh) — shared helper library
- [Claude Code hooks reference](https://docs.claude.com/en/docs/claude-code/hooks) — upstream event taxonomy
- [Security & Hardening](security-hardening.md) — tool pinning and drift detection that build on this hook system
