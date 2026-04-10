---
name: safe-commit
description: Commit changes with staged-diff secret scanning and branch protection guardrails. Use when user says "safe commit", "safe-commit", or "commit with checks". Do NOT use for regular commits — this is an opt-in extra layer on top of normal git workflow.
---

# Safe Commit

Adds two guardrails that existing hooks don't cover:

1. **Staged-diff secret scanning** — catches secrets that were `git add`ed (e.g., `.env` files, hardcoded tokens)
2. **Branch protection warning** — alerts when committing directly to main/master

## What This Adds (vs existing hooks)

| Check | Existing hook | safe-commit |
|-------|:---:|:---:|
| Secrets in Write/Edit content | `pre-edit-guard.sh` | -- |
| Schema validation | `agents_schema_guard.sh` | -- |
| Filesystem sandboxing | `check_filesystem_path.sh` | -- |
| Secrets in `git diff --cached` | -- | `scan-staged.sh` |
| Direct commit to main/master | -- | `check-branch.sh` |

## Workflow

1. Run `scripts/scan-staged.sh` to check staged diff against shared secret patterns
2. Run `scripts/check-branch.sh` to verify you're not on a protected branch
3. If both pass, proceed with the commit
4. If either fails, report the issue and ask the user how to proceed

## On-Demand Hook (demo pattern)

This skill demonstrates the **on-demand hook pattern**: a `PreToolUse` hook registered in `.claude/settings.json` that intercepts `git commit` Bash commands and runs both checks automatically before the commit proceeds.

**Hook**: `scripts/pre-commit-hook.sh`
- Registered as a `PreToolUse` hook with `"matcher": "Bash"`
- Reads the command from stdin JSON, checks if it matches `git commit`
- If not a commit command, exits silently (zero overhead for non-commit operations)
- If it is a commit: runs `scan-staged.sh` (blocks on secrets) then `check-branch.sh` (warns on main/master)

**This is the reference implementation** for skill-scoped hooks. The pattern:
1. Hook script reads tool input from stdin
2. Filters to only relevant commands (narrow matcher)
3. Composes existing scripts rather than duplicating logic
4. Blocks on hard failures, warns on soft failures

### Manual usage

You can also run the scripts directly:

```bash
bash .claude/skills/safe-commit/scripts/scan-staged.sh
bash .claude/skills/safe-commit/scripts/check-branch.sh
```

## Gotchas

- This skill reuses `scripts/hooks/lib/secret-patterns.txt` — do not duplicate patterns into a separate file
- The staged-diff scan only catches secrets in the diff output, not in unchanged parts of staged files — it complements, not replaces, the existing pre-edit hooks
- Branch protection is a warning, not a block — there are legitimate reasons to commit to main (e.g., CI fixes, sole-maintainer repos)
- If you add new secret patterns, add them to the shared `secret-patterns.txt` so all hooks benefit
