---
name: wrap-up
description: End-of-session wrap-up — updates logs, progress report, handoffs, wiki, indexes; surveys every repo for unpushed work and open PRs; pushes to main
---

# Session Wrap-Up

Update all documentation artifacts to reflect work completed in this session, then push to main.

## Resolving project values

This skill uses three values. Resolve them once, at the start, rather than
hardcoding them:

```bash
LOG_REPO=$(jq -r '.log_repo_name' .archetype-manifest.json)      # e.g. repos/$LOG_REPO
GH_OWNER=$(jq -r '.template_values.GH_USER' .archetype-manifest.json)
USER_NAME=${SESSION_USER:-$(git config user.name)}
```

`$USER_NAME` is the per-user directory name under `logs/progress/` and `notes/`.
If `SESSION_USER` is unset and `git config user.name` looks wrong, ask rather
than guessing — writing to the wrong user's directory is hard to notice later.

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

### 5. Unpushed-Work Survey

Survey every repo under `repos/` plus the root repo for unpushed work and open PRs.

For each repo, report:

```bash
# 1. Survey every git repo (root + repos/*)
for repo in . repos/*/; do
  [ -d "$repo/.git" ] || continue
  name=$([ "$repo" = "." ] && echo "governance-root" || basename "$repo")
  [ "$name" = "$LOG_REPO" ] && continue

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

# 3. For any PR that's old or looks important, fetch its CI/merge state:
#    gh pr view <N> -R <owner/repo> --json mergeable,mergeStateStatus,reviewDecision,updatedAt
#    State values: CLEAN (mergeable, CI passed), UNSTABLE (CI failing/pending),
#                  DIRTY (conflicts), BLOCKED (review required), UNKNOWN (recompute pending)
```

Interpret the output and **explicitly classify each finding** before asking the user:

- **Stale leftovers** — old session-auto-commit branches with `[gone]` upstream, branches matching squash-merged PRs (verify by checking if branch tip's tree matches a recent main commit), regenerable junk (e.g., session branches that re-introduce gitignored files). Note these as "stale, no action" with the reason.
- **Genuine unpushed work** — branches with substantive commits not on any remote ref, uncommitted changes that look intentional, open PRs awaiting action.
- **Open PRs** — fetch CI/merge state per PR. UNSTABLE/FAILING/DIRTY means investigate; CLEAN means the maintainer just needs to review.

For each genuine finding, check `MAINTAINERS.json` to determine whether the current user is a maintainer of that repo. Then ask the user what to do.

### 6. Commit and Push Knowledge

Stage and commit all documentation changes, then push to the knowledge repo:

```bash
bash scripts/utils/push-logs.sh
```

This handles:
- Pulling latest from the log repo's main
- Staging all logs/notes changes
- Regenerating the handoff index
- Committing and pushing to the log repo's main branch

### 7. Summary

End with a summary of what was updated:

```
## Wrap-Up Complete

| Artifact | Status |
|----------|--------|
| Progress report | Created/Updated |
| Handoffs | Updated/No active handoffs |
| Wiki | N articles created/updated / No wiki-worthy content |
| Indexes | Rebuilt |
| Unpushed work | repo-name: pushed/PR created/kept local / No findings |
| Open PRs (authored by me) | N open / list per repo with CI state, or No open PRs |
| Push to main | Success/Failed (reason) |
```

## Guidelines

- Be factual and specific — include file paths and concrete results
- Note deferred work explicitly so the next session can pick it up
- Keep progress entries self-contained — a reader shouldn't need other files to understand what happened
- Wiki compilation is optional per session — only create/update articles for genuinely reusable knowledge
