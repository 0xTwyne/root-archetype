---
name: research-intake
description: Ingest external sources into structured knowledge base. Use when user provides research material, URLs, papers, or says "research intake", "ingest this", "add to knowledge base". Do NOT use for querying existing knowledge (use project-wiki instead).
---

# Research Intake

Ingest external sources into the project's structured knowledge base.

Use when:

- User provides research material, URLs, papers, or articles
- User says "research intake", "ingest this", "add to knowledge base"
- Incorporating findings from external benchmarks or experiments

Do not use when:

- Querying existing knowledge (use project-wiki)
- Writing or editing application code
- Working on handoffs or session management

## Workflow

1. **Fetch** — Retrieve the source content (URL, file, or user-provided text)
2. **Dedup** — Check `knowledge/research/intake_index.yaml` for existing entries with the same URL or title
3. **Score** — Assess relevance to project using `knowledge/taxonomy.yaml` categories
4. **Extract** — Summarize key findings, decisions, or data points
5. **Categorize** — Map to taxonomy categories; propose new categories if none fit
6. **Store** — Write structured deep-dive to `knowledge/research/deep-dives/<slug>.md`
7. **Index** — Append entry to `knowledge/research/intake_index.yaml`

## Deep-Dive Format

```markdown
# <Title>

**Source**: <URL or citation>
**Ingested**: <YYYY-MM-DD>
**Categories**: <comma-separated taxonomy categories>
**Confidence**: <verified|inferred|external>

## Summary

<2-3 paragraph summary of key findings>

## Key Takeaways

- <Actionable finding 1>
- <Actionable finding 2>

## Relevance to Project

<How this applies to current work>
```

## Index Entry Format

```yaml
- title: "<Title>"
  source: "<URL>"
  date: "<YYYY-MM-DD>"
  categories: [<category1>, <category2>]
  deep_dive: "deep-dives/<slug>.md"
  actioned: false
```

## Gotchas

- Always check for duplicates before ingesting — the index is the source of truth
- Set `actioned: false` on new entries; the project-wiki lint pass flags un-actioned entries
- Confidence level `external` means the finding hasn't been validated against project code
- Deep-dive files are append-only; update the index entry rather than editing deep-dives
