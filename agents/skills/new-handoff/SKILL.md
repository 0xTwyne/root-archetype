---
name: new-handoff
description: Create a structured handoff document for cross-session or cross-agent work tracking. Use when user says "new handoff", "create handoff", "track work item", "document this for next session", or needs to pass work to another session/agent. Do NOT use for reading or updating existing handoffs.
---

# New Handoff

Create a properly structured handoff document in `notes/<user>/handoffs/`.

## What to do

1. Ask the user for a **title** and brief **context** if not already clear.

2. Generate a kebab-case filename from the title (e.g. "Auth Middleware Rewrite" → `auth-middleware-rewrite.md`).

3. **Resolve the log repo path**: read `.archetype-manifest.json` for `log_repo_name`, then look in `repos/<name>/`. All handoffs live in the log repo.

4. Check for duplicate filenames in the log repo:
   ```bash
   find <log-repo>/notes/ -path "*/handoffs/*.md" 2>/dev/null | grep -i "<filename>"
   ```

5. Create the handoff using the template in `assets/handoff-template.md`. Fill in:
   - **Status**: `active`
   - **Created**: today's date
   - **Source Repo**: from `.session-identity` `root_repo` field
   - **Source Branch**: current git branch
   - **Context**: from user input
   - Leave Remediation Plan and Acceptance Criteria as skeleton sections for the user to fill.

6. Place in `<log-repo>/notes/<user>/handoffs/<filename>.md`.

## Handoff lifecycle

- `notes/<user>/handoffs/` — Active/in-progress work
- `notes/<user>/handoffs/completed/` — Done (move manually)
- `notes/handoffs/INDEX.md` — Aggregation index across users

## Gotchas

- Always check for existing handoffs with similar names before creating — duplicates cause confusion
- The filename must be kebab-case and end in `.md`
- Status field must be one of: `active`, `blocked`, `completed`
- Handoffs should be self-contained — another session reading it cold should understand the full context without asking questions
- Do not create handoffs for trivial tasks that fit in a single session — handoffs are for work that spans sessions or agents
