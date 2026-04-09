---
name: project-wiki
description: Lint, query, and maintain the project knowledge base. Use when auditing KB health, searching for compiled knowledge, or checking governance hygiene. Do not use when ingesting new research (use research-intake if available).
---

# Project Wiki

Use this skill to maintain and query the project's knowledge base.

Use when:

- Auditing knowledge base health (orphan handoffs, stale entries, contradictions)
- Asking "what do we know about X?" and getting compiled answers with citations
- Checking governance hygiene before handoff reviews or nightshift runs
- Verifying that all intake entries have been actioned

Do not use when:

- Ingesting new research material (use the research-intake skill if available)
- Writing or editing content directly
- Working on application code or running benchmarks

## Configuration

Reads `wiki.yaml` at repo root for paths, thresholds, and enabled lint passes.
Falls back to sensible defaults if `wiki.yaml` is not present.
See `_templates/wiki.yaml.template` for the config schema.

## Operations

### Operation 1 — Lint

Audit the knowledge base for hygiene issues. Run via:
```
python3 .claude/skills/project-wiki/scripts/lint_wiki.py
```

Or invoke this skill with: "lint the knowledge base" / "check KB health"

#### Lint Passes

1. **Orphan handoff detection**: Find handoff files not referenced by any index
2. **Stale entry flagging**: Flag files not modified within threshold days
3. **Contradictory status detection**: Flag status vs directory mismatches
4. **Un-actioned intake detection**: Find intake entries that should have handoffs
5. **Missing cross-reference detection**: Check markdown links point to existing files

See `references/lint-passes.md` for detailed pass documentation.

#### Output

Structured report with severity levels: ERROR (must fix), WARNING (should review), INFO.
Exit code 1 if any ERRORs, 0 otherwise.

### Operation 2 — Query

Answer questions about compiled knowledge with citations.

Invoke with: "what do we know about {topic}?"

```
python3 .claude/skills/project-wiki/scripts/query_wiki.py "{query}" --human
```

Searches intake index, handoffs, and deep-dives. Returns ranked results.

## Gotchas

- Lint only reports — does NOT auto-fix.
- Query synthesizes from existing KB — does NOT fetch external information.
- Scaling thresholds in `wiki.yaml` are advisory only.
