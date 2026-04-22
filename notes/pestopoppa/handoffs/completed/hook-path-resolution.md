# Handoff: Hook Path Resolution — CWD-Dependent Failures

**Status**: completed
**Created**: 2026-04-22
**Priority**: high (affects every new repo spawned from root-archetype)
**Estimated scope**: settings.json template + optional init-project.sh patch

---

## Problem

All hook commands in `.claude/settings.json` use bare relative paths:

```json
"command": "bash scripts/hooks/check_secrets_read.sh"
```

Claude Code runs hook commands from the **project directory** for most hook types, but the CWD is not guaranteed to be the project root in all contexts — notably during worktree operations, subagent execution, or if the user starts Claude Code from a subdirectory. When the CWD isn't the project root, bash cannot find the script and emits:

```
bash: scripts/hooks/check_secrets_read.sh: No such file or directory
```

The scripts have internal CWD guards (`if [[ ! -f "scripts/hooks/..." ]]; then exit 0; fi`) but these never execute because bash fails to locate the file before the script runs.

**Observed in**: sangha-root (workspace), 2026-04-22. SessionStart hooks work (CWD is project root at session init), but PreToolUse and PostToolUse hooks fail intermittently.

---

## Verified Fix (applied locally in sangha-root)

Prefix all hook commands with `${CLAUDE_PROJECT_DIR:-.}/`:

```json
"command": "bash \"${CLAUDE_PROJECT_DIR:-.}/scripts/hooks/check_secrets_read.sh\""
```

Claude Code sets `CLAUDE_PROJECT_DIR` in the hook execution environment, so paths resolve to absolute. The `:-.` fallback preserves relative resolution if the variable is somehow unset.

**All 5 default hooks need this fix:**
- `scripts/hooks/session-start.sh` (SessionStart)
- `scripts/hooks/session-end.sh` (SessionEnd)
- `scripts/hooks/check_secrets_read.sh` (PreToolUse: Read|Glob|Grep|Bash)
- `scripts/hooks/check_filesystem_path.sh` (PreToolUse: Write|Edit)
- `scripts/hooks/post-tool-use-audit.sh` (PostToolUse)

---

## Tasks for Root-Archetype

### A. Update `.claude/settings.json` template

Apply the `${CLAUDE_PROJECT_DIR:-.}/` prefix to all hook command paths in the archetype's settings.json. This is the source template that `init-project.sh` copies into new repos.

### B. Consider `init-project.sh` impact

Check whether `init-project.sh --engine claude` copies or generates `.claude/settings.json`. If it copies the template verbatim, fixing the template (Task A) is sufficient. If it generates the file programmatically, the generation logic also needs the prefix.

### C. Evaluate whether CWD guards are still needed

With absolute paths, the scripts will always be found by bash. The internal CWD guards (`if [[ ! -f "scripts/hooks/..." ]]`) now serve a different purpose: they detect if the script is being run outside a root-archetype project (e.g., if settings.json is copied but scripts/ isn't). Decide whether to:
- Keep them as-is (belt and suspenders)
- Update them to also use `$CLAUDE_PROJECT_DIR` for consistency
- Remove them (the absolute path already guarantees the script exists)

### D. Optional: audit hook scripts for other relative-path assumptions

Some hooks internally reference files with relative paths (e.g., `source scripts/hooks/lib/hook-utils.sh`). Most already resolve via `$SCRIPT_DIR` or `$PROJECT_DIR`, but a quick audit would confirm no other relative-path fragility exists.

---

## Acceptance Criteria

1. Archetype `.claude/settings.json` uses `${CLAUDE_PROJECT_DIR:-.}/` prefix on all hook commands
2. New repos created via `init-project.sh` inherit the fix
3. No "No such file or directory" errors for hooks regardless of CWD context

---

## Resolution (2026-04-22)

All 4 tasks completed:

- **Task A**: `agents/engines/claude/settings.json.tmpl` — all 5 hook commands now use `${CLAUDE_PROJECT_DIR:-.}/` prefix
- **Task B**: Confirmed `generate-engine.sh` does verbatim `cp` of template — no changes needed; template fix propagates automatically to new repos via `init-project.sh`
- **Task C**: Internal CWD guards evaluated — hooks use `SCRIPT_DIR`/`BASH_SOURCE` pattern which is already CWD-independent once the script is found; no changes needed
- **Task D**: Audited all hooks — `check_filesystem_path.sh` was the only outlier (no `PROJECT_DIR` resolution, no `hook-utils.sh`); modernized to match standard pattern

Additional preventive changes:
- `scripts/hooks/README.md` — expanded "Enabling Optional Hooks" with prefix pattern and warning
- `agents/skills/init-wizard/SKILL.md` — Step 6 now documents required command format for wired hooks

## References

- Local fix applied in: `/workspace/.claude/settings.json` (sangha-root, gitignored)
- Related completed handoff: [05-hook-consolidation.md](../completed/05-hook-consolidation.md)
