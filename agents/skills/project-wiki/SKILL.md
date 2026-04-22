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

#### Compilation Modes

**Per-member compilation** (any team member):
```
python3 agents/skills/project-wiki/scripts/compile_sources.py --user <username>
```
- Reads: `<log-repo>/logs/progress/<user>/`, `<log-repo>/notes/<user>/`
- Writes: `<log-repo>/wiki/<user>/`

**Master compilation** (maintainer only):
```
python3 agents/skills/project-wiki/scripts/compile_sources.py --master
```
- Reads: all `<log-repo>/wiki/<user>/` + `<log-repo>/notes/` + `<log-repo>/logs/`
- Writes: `<root-repo>/knowledge/wiki/`

When a maintainer compiles their personal wiki, master wiki recompilation
happens automatically unless `--skip-master` is passed.

Resolve the log repo from `.archetype-manifest.json` (`log_repo_name`) via
the `repos/` directory. Override with `--log-repo <path>` if needed.

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

1. Check if a wiki page already exists in `knowledge/wiki/` for that topic
2. If yes: read the existing page, merge new findings, update the "Last compiled" date
3. If no: create a new page following this structure:

```markdown
# <Topic Title>

**Category**: <from knowledge/taxonomy.yaml>
**Confidence**: <verified|inferred|external>
**Last compiled**: <YYYY-MM-DD>
**Sources**: <N> documents from <M> users

## Summary

<2-4 paragraph synthesized overview>

## Key Points

- <Actionable finding or decision>
- <Pattern or convention discovered>

## Source References

- [source title](../../notes/<user>/handoffs/...) — <what this source contributed>
- [progress log](../../logs/progress/<user>/2026-04-10.md) — <what was observed>
```

Filename convention: `knowledge/wiki/<kebab-case-topic>.md`

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

## Gotchas

- Lint only reports — does NOT auto-fix.
- Query synthesizes from existing KB — does NOT fetch external information.
- Compile reads all user streams but writes only to shared locations (`knowledge/`, `notes/handoffs/INDEX.md`).
- Scaling thresholds in `wiki.yaml` are advisory only.
