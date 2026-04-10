---
name: research-intake
description: Ingest external sources into structured knowledge base
---

# Research Intake

## Trigger

`/research-intake <url1> [url2] ...` or when user provides research material

## Workflow

1. **Fetch**: Download/read each provided source
2. **Dedup**: Check `knowledge/research/intake_index.yaml` -- skip already-processed sources
3. **Score**: Rate source relevance to project (1-5 scale based on taxonomy match)
4. **Extract**: Produce structured summary in `knowledge/research/deep-dives/`
5. **Index**: Append entry to `knowledge/research/intake_index.yaml`
6. **Categorize**: Map to `knowledge/taxonomy.yaml` categories (suggest new if needed)

## Output Format

Each deep-dive file: `knowledge/research/deep-dives/YYYY-MM-DD-slug.md`

```markdown
# {Title}

**Source**: {url}
**Ingested**: {date}
**Categories**: {taxonomy categories}
**Relevance**: {1-5}

## Key Takeaways
[3-5 bullet points]

## Detailed Notes
[Structured content]

## Action Items
[What this means for the project, if anything]
```

## Dedup Rules

- Same URL -- skip (exact match in intake_index.yaml)
- Same content hash -- skip (content-level dedup)
- Same topic, different source -- process but cross-reference existing entry
