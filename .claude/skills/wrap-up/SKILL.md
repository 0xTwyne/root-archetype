---
name: wrap-up
description: End-of-session wrap-up — updates logs, progress report, handoffs, wiki, indexes; surveys every repo for unpushed work and open PRs; pushes to main. Use when the user runs /wrap-up, says "wrap up", or wants a mid-session checkpoint pushed. Do NOT use for an ordinary commit — use safe-commit for that.
---

# Session Wrap-Up

Update all documentation artifacts to reflect work completed in this session, then push to main.

## Resolve who and where, first

Do not hardcode a username. Every path below is per-user, and writing into
someone else's directory is the one mistake here that is hard to notice and
annoying to unpick.

**Each Bash tool call is a fresh shell — variables do not survive between them.**
So this is not a one-time preamble: paste this block at the top of *every* Bash
call below that uses `$USER_NAME`, `$LOG_REPO` or `$GH_OWNER`. Skipping it is
silent, not loud: `$GH_OWNER` expands to the empty string and `gh search prs
--owner ""` searches nothing rather than erroring in a way you would notice.

```bash
USER_NAME=$(jq -r '.user // empty' .session-identity 2>/dev/null || true)
if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "null" ]; then
  USER_NAME=$(gh api user --jq .login 2>/dev/null || git config user.name 2>/dev/null || true)
  # session-start.sh sanitizes the same way; matching it keeps one person from
  # ending up with two directories ("Ada Lovelace" -> AdaLovelace) depending on
  # whether gh happened to be authenticated.
  USER_NAME=$(printf '%s' "$USER_NAME" | tr -cd 'a-zA-Z0-9_-')
fi

# tr -d '\r' on every jq read: the Windows jq writes stdout in text mode, so a
# bare CR rides along and survives $( ). Unstripped, LOG_REPO names no directory
# and GH_OWNER corrupts every gh URL built from it.
LOG_REPO=$(jq -r '.log_repo_name' .archetype-manifest.json | tr -d '\r')      # -> repos/$LOG_REPO
GH_OWNER=$(jq -r '.template_values.GH_USER' .archetype-manifest.json | tr -d '\r')
```

Written as `if/then` deliberately. The earlier one-liner
(`[ -z "$X" ] || [ "$X" = "null" ] && X=...`) returns **exit 1 on the happy
path** — when the name is valid both tests fail and `&&` short-circuits — so a
Bash call ending on that line reports failure while having worked correctly.

`.session-identity` is written by `session-start.sh`, which resolves the user
from `gh api user --jq .login` and falls back to git config. If `$USER_NAME`
comes out empty or looks wrong, ask rather than guessing.

### Then check the log repo is real, before writing anything

```bash
git -C "repos/$LOG_REPO" rev-parse --git-dir >/dev/null 2>&1 \
  && echo "log repo OK" || echo "STOP: repos/$LOG_REPO is not a git repo"
```

If this fails, **stop and tell the user to run `bash scripts/bootstrap.sh`.** Do
not proceed and do not improvise another location.

Logs, progress reports, notes, handoffs and the wiki all live in the log repo.
There is no second location and no degraded mode — the root repo is not a place
any of them belong. `repos/$LOG_REPO/` is gitignored by root, so writing there
without the clone present produces an ordinary untracked directory and no error
at all.

`push-logs.sh` now aborts in this situation rather than silently redirecting,
and `session-start.sh` warns at the top of the session, so you should never
reach this check in a broken state. It stays as the last line of defence
because the failure it guards against is invisible: files get created, nothing
errors, and the summary in step 7 would report Success over a session whose
entire written record exists in no repository.

## Steps

### 1. Progress Report

- Create or update: `repos/$LOG_REPO/logs/progress/$USER_NAME/YYYY-MM-DD.md`
- Use this format: `# Progress: YYYY-MM-DD` followed by `## Wrap-up: HH:MM UTC` with sections: What was done, Key decisions, Deferred / next (see existing reports for reference)
- Be factual and specific — include file paths, concrete results, and measured values

### 2. Handoff Updates

- Check `repos/$LOG_REPO/notes/$USER_NAME/handoffs/` for active handoffs that were advanced by this session
- Check off completed items, add new findings, note any blockers discovered
- If a handoff is fully complete, note the completion date and link to the progress report
- For new cross-user work handoffs: create `repos/$LOG_REPO/notes/$USER_NAME/handoffs/YYYY-MM-DD_to-<recipient>_<topic-slug>.md`

### 3. Index Updates

Rebuild all auto-generated indexes:

```bash
bash scripts/build-indexes.sh
```

This updates:
- `repos/$LOG_REPO/logs/progress/INDEX.md` — progress report index
- `repos/$LOG_REPO/notes/INDEX.md` — notes/handoffs/plans index
- `repos/$LOG_REPO/wiki/INDEX.md` — wiki article index with scope lookup
- `repos/$LOG_REPO/wiki/STALENESS.md` — articles whose sources changed since `updated:`

The root `scripts/build-indexes.sh` is a thin wrapper; the real builder lives in
the knowledge repo and owns all four artifacts.

### 4. Wiki Compilation

Check if this session produced knowledge worth capturing in the wiki:

- Protocol insights, cross-repo integration discoveries, or operational gotchas learned
- Incident details or resolution methodology
- New tool/process documentation

If yes:
1. Check `repos/$LOG_REPO/wiki/INDEX.md` for existing articles
2. If an existing article covers the topic: update it with new findings, bump the `updated:` date in YAML frontmatter
3. If no article exists and the knowledge is reusable: create one following `repos/$LOG_REPO/wiki/schema.md` — YAML frontmatter, a category directory, and real `sources:` paths so staleness detection works
4. If nothing wiki-worthy was learned this session: skip this step

Also glance at `repos/$LOG_REPO/wiki/STALENESS.md`. If this session
touched a source that made an article stale, refreshing it now is cheaper than
letting the drift accumulate.

### 5. Audit Log Verification

Verify the session's audit log is consistent:
- `SESSION_START` and `SESSION_END` are present
- Every significant task has `TASK_START` and `TASK_END`
- Modified files have `FILE_MODIFY` entries
- Test runs (if any) have `TEST_RUN` entries with counts

The audit log is at
`repos/$LOG_REPO/logs/audit/$USER_NAME/tool-calls-YYYY-MM-DD-<session>.jsonl`,
and the cross-session summary is `repos/$LOG_REPO/logs/agent_audit.log`.

Both live in the log repo and nowhere else. If you find audit entries under the
ROOT repo's `logs/`, something is resolving the log repo wrongly — that is a
finding, not a duplicate to tidy away. This has happened: a writer resolving to
`<root>/logs` unconditionally kept appending there for months, accumulating
entries that existed in the log repo nowhere at all. Nothing errored.

### 6. Unpushed-Work Survey

Survey every repo under `repos/` plus the root repo for unpushed work and open PRs.

For each repo, report:

```bash
# Fresh shell — re-derive. See "Resolve who and where, first", including the
# tr -d '\r' on each jq read.
LOG_REPO=$(jq -r '.log_repo_name' .archetype-manifest.json | tr -d '\r')
GH_OWNER=$(jq -r '.template_values.GH_USER' .archetype-manifest.json | tr -d '\r')

# 1. Survey every git repo (root + repos/*)
for repo in . repos/*/; do
  [ -d "$repo/.git" ] || continue
  name=$([ "$repo" = "." ] && echo "<project-root>" || basename "$repo")
  [ "$name" = "$LOG_REPO" ] && continue   # handled by push-logs.sh in step 8

  uncommitted=$(git -C "$repo" status --porcelain 2>/dev/null | head -10)
  ahead_current=$(git -C "$repo" log --oneline @{u}..HEAD 2>/dev/null | head -10)
  ahead_branches=$(git -C "$repo" for-each-ref refs/heads/ --format='%(refname:short)' | \
    while read b; do
      n=$(git -C "$repo" log --oneline "origin/main..$b" 2>/dev/null | wc -l)
      [ "$n" -gt 0 ] && [ "$b" != "$(git -C "$repo" branch --show-current)" ] && \
        echo "  $b: $n commits ahead of origin/main"
    done | head -20)
  no_upstream=$(git -C "$repo" for-each-ref refs/heads/ --format='%(refname:short) %(upstream:trackshort)' | \
    awk '$2 == "" {print "  " $1}' | head -10)

  if [ -n "$uncommitted" ] || [ -n "$ahead_current" ] || [ -n "$ahead_branches" ] || [ -n "$no_upstream" ]; then
    echo "=== $name ==="
    [ -n "$uncommitted" ]    && echo "  uncommitted:"    && echo "$uncommitted"    | sed 's/^/    /'
    [ -n "$ahead_current" ]  && echo "  unpushed (current branch):" && echo "$ahead_current" | sed 's/^/    /'
    [ -n "$ahead_branches" ] && echo "  ahead-of-main branches:" && echo "$ahead_branches"
    [ -n "$no_upstream" ]    && echo "  branches without upstream:" && echo "$no_upstream"
  fi
done

# 2. Open PRs authored by the current user across the project's repos
gh search prs --owner "$GH_OWNER" --author @me --state open \
  --json number,title,url,repository \
  --jq '.[] | "  \(.repository.nameWithOwner)#\(.number) — \(.title)"' \
  | head -30

# 3. Open issues across the project's repos. A collaborator may file one
#    instead of writing a handoff — branches, working trees and PRs will not
#    surface it, and it is easy to miss for weeks.
for repo in $(gh repo list "$GH_OWNER" --limit 50 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); do
  gh issue list --repo "$repo" --state open --limit 10 \
    --json number,title,author,updatedAt \
    --jq '.[] | "  '"$repo"'#\(.number) \(.author.login): \(.title)"' 2>/dev/null
done | head -30

# 4. For any PR that's old or looks important, fetch its CI/merge state:
#    gh pr view <N> -R <owner/repo> --json mergeable,mergeStateStatus,reviewDecision,updatedAt
#    State values: CLEAN (mergeable, CI passed), UNSTABLE (CI failing/pending),
#                  DIRTY (conflicts), BLOCKED (review required), UNKNOWN (recompute pending)
```

Interpret the output and **explicitly classify each finding** before asking the user:

- **Stale leftovers** — old session-auto-commit branches with `[gone]` upstream, branches matching squash-merged PRs (verify by checking if branch tip's tree matches a recent main commit), regenerable junk (e.g., session branches that re-introduce gitignored files). Note these as "stale, no action" with the reason.
- **Genuine unpushed work** — branches with substantive commits not on any remote ref, uncommitted changes that look intentional, open PRs awaiting action.
- **Open issues** — an issue is a handoff someone chose not to file as one. Read any that are new since the last wrap-up and say what they ask for; do not just count them.
- **Open PRs** — fetch CI/merge state per PR. UNSTABLE/FAILING/DIRTY means investigate; CLEAN means the maintainer just needs to review.

For each genuine finding, check `MAINTAINERS.json` to determine whether the current user is a maintainer of that repo. Then ask the user what to do.

### 7. Wiki Refresh (Drain Stale Backlog)

This drains the *shared* staleness backlog — not a check of this session's own
topics. Every session takes a turn refreshing a few articles so stale entries
never accumulate team-wide.

1. Read `repos/$LOG_REPO/wiki/STALENESS.md` (ordered stalest-first) and take the
   **top 3 entries**, regardless of whether they relate to this session's work or
   this user's articles.
2. For each of the 3 articles:
   - Read the article and the changed sources it lists as stale.
   - Update the article to reflect the changed sources, and bump its `updated:`
     frontmatter date.
   - If a source change requires domain judgment this session does not have
     (e.g. a domain call outside its expertise), skip that
     article and record the skip — and why — in the progress report rather than
     guessing.
3. Run `bash scripts/build-indexes.sh` to regenerate `STALENESS.md` and
   `INDEX.md` after the updates.
4. Include the wiki changes in the push flow in the next step.

If `STALENESS.md` reports every article fresh, say so and move on — an empty
backlog is a normal state, not a step to force.

### 8. Commit and Push Knowledge

Stage and commit all documentation changes, then push to the knowledge repo:

```bash
bash scripts/utils/push-logs.sh
```

This handles:
- Pulling latest from the log repo's main
- Staging all logs/notes changes
- Regenerating the handoff index
- Committing and pushing to the log repo's main branch

### 9. Summary

End with a summary of what was updated:

```
## Wrap-Up Complete

| Artifact | Status |
|----------|--------|
| Progress report | Created/Updated |
| Handoffs | Updated/No active handoffs |
| Wiki | N articles created/updated / No wiki-worthy content |
| Wiki refresh (stale backlog) | N drained / backlog empty |
| Audit log | Consistent / N gaps found |
| Indexes | Rebuilt |
| Unpushed work | repo-name: pushed/PR created/kept local / No findings |
| Open PRs (authored by me) | N open / list per repo with CI state, or No open PRs |
| Push to main | Success/Failed (reason) |
```

## Guidelines

- The running session's own audit file
  (`repos/$LOG_REPO/logs/audit/$USER_NAME/tool-calls-<date>-<session>.jsonl`) is expected to be
  modified — the PostToolUse hook appends to it on every tool call, including
  the ones this wrap-up is making. It is a live log, not uncommitted work, and
  the session-end hook commits it. Do not report it as a finding; do report any
  *other* audit file that is dirty, since that means a finished session never
  ended cleanly.
- Be factual and specific — include file paths and concrete results
- Note deferred work explicitly so the next session can pick it up
- Keep progress entries self-contained — a reader shouldn't need other files to understand what happened
- Wiki compilation is optional per session — only create/update articles for genuinely reusable knowledge

## Gotchas

- **Each Bash tool call is a fresh shell.** `$USER_NAME`, `$LOG_REPO` and
  `$GH_OWNER` do not survive between calls. Re-derive them in every block that
  uses them. The failure is silent: `gh search prs --owner ""` searches nothing
  and reports no error.
- **Never write to the root repo.** Logs, progress reports, notes, handoffs and
  the wiki live in the log repo only. Root is not a fallback. It still carries
  April-era duplicates from before the split because an earlier version of the
  resolver treated it as one.
- **Check the log repo exists before writing anything.** `repos/<log-repo>/` is
  gitignored by root, so writing there without the clone present creates an
  untracked directory and raises no error at any stage.
- **Do not report the running session's own audit file as a finding.** The
  PostToolUse hook appends to it on every call, including this wrap-up's own.
  A *different* audit file being dirty is a real finding — it means a finished
  session never ended cleanly.
- **`[ -z "$X" ] || [ "$X" = "null" ] && X=...` returns exit 1 on the happy
  path.** Both tests fail when the value is valid, so `&&` short-circuits. A
  Bash call ending on that line reports failure while having worked. Use
  `if/then`.
- **A count hides an open issue.** Step 5 lists issues rather than counting them
  because a single open issue reads as noise until someone opens it. A
  collaborator who files an issue instead of a handoff is easy to miss for weeks.
