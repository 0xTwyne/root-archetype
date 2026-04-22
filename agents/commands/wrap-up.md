# /wrap-up — Mid-Session Save & Wiki Compile

Save current progress, push logs to main, and recompile the local wiki.
Use this anytime during a session to checkpoint your work — not just at the end.
The session-end hook does steps 1–3 automatically; this command lets you do it
manually and adds wiki compilation.

## Steps

### Step 1: Write Progress Report

Resolve the log repo path from `.archetype-manifest.json` (`log_repo_name`) via `repos/<name>`.
Append a progress entry to `<log-repo>/logs/progress/<user>/YYYY-MM-DD.md`.
Follow the existing format in that file (or create it if missing):

```markdown
## Wrap-up: <HH:MM UTC>

### What was done
- <bullet summary of work completed since last checkpoint>

### Key decisions
- <any decisions made and their rationale>

### Deferred / next
- <anything left undone or handed off>
```

Determine `<user>` from the `SESSION_USER` environment variable, or fall back
to `git config user.name`, or ask.

### Step 2: Update Handoffs (if applicable)

If any `<log-repo>/notes/<user>/handoffs/active/*.md` files relate to the work done:
- Check off completed items
- Add findings or blockers discovered
- Move fully completed handoffs to `<log-repo>/notes/<user>/handoffs/completed/`

If no handoff files are relevant, skip this step.

### Step 3: Push Logs to Main

Run the log push script (safe to call mid-session — uses a worktree):

```bash
bash scripts/utils/push-logs.sh
```

In split mode, this commits and pushes to the log repo directly.
In single-repo mode, this pushes via worktree to main.

### Step 4: Wiki Compilation

Run the source manifest scanner:

```bash
python3 agents/skills/project-wiki/scripts/compile_sources.py
```

If `total_new` is 0, report "Wiki is up to date" and skip to Step 5.

If sources need compilation, follow the compile workflow from the project-wiki
skill (Operation 3 in `agents/skills/project-wiki/SKILL.md`):
1. Read the listed source files
2. Cluster by topic, check existing `knowledge/wiki/` pages
3. Create or update wiki pages (synthesize, don't copy)
4. Update taxonomy in `knowledge/taxonomy.yaml` if new categories emerged
5. Regenerate handoff index: `bash scripts/utils/generate-handoff-index.sh`
6. Update compile timestamp: `python3 agents/skills/project-wiki/scripts/compile_sources.py --touch`

### Step 5: Commit Changes

In split mode, commit to both repos:

**Log repo** (progress, handoffs, per-member wiki):
```bash
cd <log-repo>
git add logs/ notes/ wiki/
git commit -m "wrap-up: progress + wiki $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

**Root repo** (only if master wiki compilation ran):
```bash
git add knowledge/
git commit -m "wrap-up: master wiki compile $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

In single-repo mode, commit everything together:
```bash
git add logs/ notes/ knowledge/
git commit -m "wrap-up: progress + wiki compile $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Do NOT push the session branch unless explicitly asked.

## Notes

- This command is safe to run multiple times per session. Each run appends a
  new timestamped section to the progress file.
- Step 3 (push-logs) is idempotent — it only pushes what's new.
- Step 4 (wiki compile) is incremental by default — only processes sources
  newer than `knowledge/research/.last_compile`.
- For a full wiki recompile, run with `--full`:
  `python3 agents/skills/project-wiki/scripts/compile_sources.py --full`
