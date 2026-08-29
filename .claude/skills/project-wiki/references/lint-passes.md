# Lint Passes Reference

Detailed documentation for each lint pass in `lint_wiki.py`.

## Pass 1: Orphan Handoff Detection

**Severity**: WARNING
**Logic**: Parse all `*-index.md` and `master-handoff-index.md` across every per-user active handoff directory (`repos/<log-repo>/notes/*/handoffs/active/`). Extract `[text](file.md)` links. Compare link targets against actual files. Flag unreferenced files.
**Exclusions**: Index files themselves are never flagged as orphans.
**Fix**: Either add the handoff to the appropriate index, or move it to the same user's `handoffs/completed/` if it's done.

## Pass 2: Stale Entry Flagging

**Severity**: WARNING (aging, >14d), ERROR (stale, >30d)
**Logic**: `os.stat().st_mtime` on each file across `repos/<log-repo>/notes/*/handoffs/active/`. Compute age in days.
**Config**: `wiki.yaml` → `lint.aging_days` (default 14), `lint.stale_days` (default 30)
**Fix**: Review the handoff — update status, add recent findings, or archive if done.

## Pass 3: Contradictory Status Detection

**Severity**: ERROR (active/ file claiming done), WARNING (completed/ file claiming active)
**Logic**: Regex `\*\*Status\*\*:\s*(.+)` on each handoff. Match against "completed"/"archived"/"done" keywords.
**Fix**: Move file to the correct directory, or update the Status line.

## Pass 4: Un-actioned Intake Detection

**Severity**: WARNING
**Logic**: Load the intake index from `<knowledge-repo>/wiki/research/intake_index.yaml` (falling back to the legacy root `knowledge/research/` for unmigrated projects). A missing index is reported as a warning rather than passing silently. Filter by verdict (`worth_investigating` or `new_opportunity`), no `handoffs_created` field, and `ingested_date` > threshold.
**Config**: `wiki.yaml` → `lint.unactioned_intake_days` (default 7)
**Fix**: Create a handoff stub, or change the verdict to `not_applicable`/`already_integrated` if no action is warranted.

## Pass 5: Missing Cross-Reference Detection

**Severity**: ERROR
**Logic**: Extract markdown links from each active handoff. Check that target `.md` files exist in any per-user `handoffs/active/` or `handoffs/completed/`. Skip external URLs and anchors.
**Fix**: Fix the link target, or remove the broken link.
