---
name: project-wiki
description: Lint, query, and maintain the project knowledge base. Use when auditing KB health, searching for compiled knowledge, or checking governance hygiene. Do not use when ingesting new research (use research-intake if available).
---

# Project Wiki

Use this skill to maintain and query the project's knowledge base.

Use when:

- Auditing knowledge base health (orphan handoffs, stale entries, contradictions)
- Asking "what do we know about X?" and getting compiled answers with citations
- Checking governance hygiene before handoff reviews
- Verifying that all intake entries have been actioned

Do not use when:

- Ingesting new research material (use the research-intake skill if available)
- Writing or editing content directly
- Working on application code or running benchmarks

## Configuration

Reads `wiki.yaml` at repo root for paths, thresholds, and enabled lint passes.
Falls back to sensible defaults if `wiki.yaml` is not present.

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

### Operation 3 — Compile

Compile per-user streams into shared knowledge artifacts.

Invoke with: "compile the wiki" / "update knowledge base"

#### Compilation Sources

Read from ALL user streams:
- `logs/progress/*/` — per-user session progress reports
- `notes/*/` — per-user notes, plans, research
- `notes/*/handoffs/` — per-user handoff documents

#### Compilation Outputs

1. **Wiki pages** written to `knowledge/wiki/`
2. **Taxonomy updates** appended to `knowledge/taxonomy.yaml` for new categories discovered during compilation
3. **Handoff index** regenerated at `notes/handoffs/INDEX.md` by scanning all `notes/*/handoffs/*.md`

#### Compilation State

Track last compilation via `knowledge/research/.last_compile` timestamp file.
The session-start hook checks this timestamp against source modification dates
and warns when recompilation is needed.

## Gotchas

- Lint only reports — does NOT auto-fix.
- Query synthesizes from existing KB — does NOT fetch external information.
- Compile reads all user streams but writes only to shared locations (`knowledge/`, `notes/handoffs/INDEX.md`).
- Scaling thresholds in `wiki.yaml` are advisory only.
