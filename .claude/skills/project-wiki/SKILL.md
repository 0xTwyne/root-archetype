---
name: project-wiki
description: Query, lint, compile, create, and refresh the project knowledge wiki at repos/$LOG_REPO/wiki/. Use when auditing KB health, searching compiled knowledge, writing a new article, or updating articles whose sources have changed. Do not use when ingesting new research (use research-intake if available).
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

#### Step 1: Generate Source Manifest

Run the manifest scanner to identify what needs compilation:

```
python3 agents/skills/project-wiki/scripts/compile_sources.py
```

For a full recompilation (ignore last compile timestamp):
```
python3 agents/skills/project-wiki/scripts/compile_sources.py --full
```

Review the output JSON. The `sources` array lists every file to consider.
The `by_type` and `by_user` summaries help decide compilation scope.
If `total_new` is 0, no compilation is needed — inform the user and stop.

#### Step 2: Read and Analyze Sources

Read the source files listed in the manifest. Prioritize:
1. Handoff documents (active first, then completed) — richest structured content
2. Progress logs — session-level observations and decisions
3. Plans and research notes — supporting context

For each source, identify:
- Key decisions made and their rationale
- Patterns discovered or conventions established
- Architecture or process changes
- Lessons learned or gotchas
- Open questions or risks

#### Step 3: Synthesize Wiki Pages

For each topic cluster identified in Step 2:

Read `repos/$LOG_REPO/wiki/schema.md` first — it is the authoritative
frontmatter spec, category list and tag vocabulary.

1. Check if a wiki page already exists in `repos/$LOG_REPO/wiki/` for that
   topic (start from its `INDEX.md`)
2. If yes: read the existing page, merge new findings, bump `updated:`
3. If no: create a new page following this structure:

```markdown
---
title: <Topic Title>
category: <concept|reference|guide|research|incident>
scope: [<repos this touches>]
tags: [<from the vocabulary in schema.md>]
sources:
  - <path relative to the governance root, or a URL>
created: <YYYY-MM-DD>
updated: <YYYY-MM-DD>
confidence: <verified|inferred|external>
---

# <Topic Title>

> One-sentence summary for agent quick-scan.

## Key Facts

- <Actionable finding or decision, linked to its source>
- <Pattern or convention discovered>

## Details

<Synthesized explanation>

## Gotchas

- <Hard-won lesson, linked to the session that found it>

## Related

- [other article](../<dir>/<slug>.md) — how it relates
```

**The frontmatter is not decoration.** `INDEX.md` and `STALENESS.md` are
generated from it. In particular `sources:` drives staleness detection — an
article is marked STALE when one of its sources has a git commit newer than
`updated:`. A page written without real source paths will never be flagged for
refresh.

Filename convention:
`repos/$LOG_REPO/wiki/<category-dir>/<kebab-case-topic>.md`, where the
directory follows the category table in `schema.md` (`concepts/`, `repos/`,
`operations/`, `research/`, `incidents/`, `tooling/`).

After writing, regenerate the indexes:

```bash
bash scripts/build-indexes.sh
```

#### Step 4: Update Taxonomy

Review `knowledge/taxonomy.yaml`. If compilation revealed categories that
don't fit existing ones, append them under `categories:` with a description.

#### Step 5: Regenerate Handoff Index

```bash
bash scripts/utils/generate-handoff-index.sh
```

#### Step 6: Update Compile Timestamp

After successful compilation:
```
python3 agents/skills/project-wiki/scripts/compile_sources.py --touch
```

Or manually:
```bash
date -u +%Y-%m-%dT%H:%M:%SZ > knowledge/research/.last_compile
```

#### Compilation Principles

- **Synthesize, don't copy.** Wiki pages distill knowledge; they are not duplicates.
- **Cross-user.** Merge findings from all users into shared topic pages.
- **Incremental by default.** Only process sources newer than `.last_compile`.
- **Preserve existing.** Update wiki pages in place; never delete content without cause.
- **Cite sources.** Every claim should trace to a source via the References section.
- **Confidence levels.** Use `verified` for tested findings, `inferred` for analysis, `external` for third-party.

### Operation 4 — Create

Scaffold a single new article, when you already know the topic and don't need a
full compile pass.

Invoke with: "create a wiki article on {topic}" / `/project-wiki create {topic}`

1. Read `repos/$LOG_REPO/wiki/schema.md` for the frontmatter spec,
   category table and tag vocabulary.
2. Pick the category and therefore the directory:

   | Category | Directory |
   |----------|-----------|
   | `concept` | `concepts/` |
   | `reference` | `repos/` |
   | `guide` | `operations/` |
   | `research` | `research/` |
   | `incident` | `incidents/` |

   Tool and process docs go in `tooling/` with whichever of `guide` /
   `reference` fits.
3. Slug the title: lowercase, hyphens, no punctuation.
4. Gather source material before writing — search
   `repos/$LOG_REPO/notes/INDEX.md`,
   `repos/$LOG_REPO/logs/progress/INDEX.md`, and the relevant repo's
   `AGENT.md` / `CLAUDE.md`. An article written from memory alone has no
   `sources:` and will never be flagged stale.
5. Write the article in the Step 3 format above.
6. Rebuild: `bash scripts/build-indexes.sh`.
7. Confirm it appears in `wiki/INDEX.md` under the expected directory. If it
   shows as `uncategorized`, or the link renders oddly, the frontmatter did not
   parse — check that `---` is the very first line.

### Operation 5 — Refresh

Update articles whose sources have moved on. This is the other half of the
compile loop: compile adds knowledge, refresh keeps it true.

Invoke with: "refresh the wiki" / `/project-wiki refresh [article]`

1. Read `repos/$LOG_REPO/wiki/STALENESS.md`. It is generated, and lists
   each stale article with the specific sources that changed and when.
2. For each stale article (or just the named one):
   a. Read the current article.
   b. Read the changed sources it names — the report gives you the paths.
   c. Work out what actually changed. A source commit does not always mean the
      article is wrong; often it is still accurate and only `updated:` needs
      bumping. Say which case it is.
   d. Present the proposed edit before writing.
   e. Apply it and set `updated:` to today.
3. Rebuild: `bash scripts/build-indexes.sh`, and confirm the article has
   dropped out of `STALENESS.md`.

Do not bump `updated:` without reading the sources. That clears the staleness
flag while leaving the article wrong, which is worse than leaving it flagged.

## Gotchas

- Lint only reports — does NOT auto-fix.
- Query synthesizes from existing KB — does NOT fetch external information.
- Compile reads user streams from the knowledge repo (`repos/$LOG_REPO/`) and writes the compiled wiki back into the same repo, at `repos/$LOG_REPO/wiki/`. Root-level `knowledge/wiki/` is cloner-facing reference documentation about the governance scaffold itself — a different artifact for a different reader, and never a compilation target. `knowledge/taxonomy.yaml` and `knowledge/research/` also stay in root.
- `INDEX.md` and `STALENESS.md` are generated. Never hand-edit them — run `bash scripts/build-indexes.sh` instead, which delegates to the knowledge repo's own builder.
- Scaling thresholds in `wiki.yaml` are advisory only.
