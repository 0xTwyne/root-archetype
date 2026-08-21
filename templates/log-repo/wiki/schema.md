# Wiki Schema

Frontmatter specification, article guidelines, and tag vocabulary for this
project's knowledge wiki.

`INDEX.md` and `STALENESS.md` are generated from the frontmatter below by
`scripts/build-indexes.sh`. An article without frontmatter still gets indexed,
but falls back to its filename and shows as `uncategorized` — so the frontmatter
is what makes an article findable.

## Frontmatter Fields

Every wiki article must open with a YAML frontmatter block, starting on line 1:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `title` | string | yes | Human-readable article title |
| `category` | enum | yes | One of: `concept`, `reference`, `guide`, `research`, `incident` |
| `scope` | string[] | yes | Repos this article touches, by directory name under `repos/` |
| `tags` | string[] | yes | Searchable terms from the vocabulary below |
| `sources` | string[] | yes | Authoritative sources — paths **relative to the governance root**, or external URLs |
| `created` | date | yes | YYYY-MM-DD first written |
| `updated` | date | yes | YYYY-MM-DD last revised |
| `confidence` | enum | no | `verified` (tested), `inferred` (analysis), `external` (third-party). Defaults to `inferred` |

## Categories and Directories

| Category | Directory | Purpose | Length target |
|----------|-----------|---------|---------------|
| `concept` | `concepts/` | Domain concepts, mechanics, the "how it actually works" | 80 lines |
| `reference` | `repos/` | Per-repo architecture, conventions, APIs | 60 lines |
| `guide` | `operations/` | Procedures, onboarding, governance workflows | 100 lines |
| `research` | `research/` | Findings, data pipelines, methodology | 80 lines |
| `incident` | `incidents/` | Post-incident knowledge, lessons learned | 50 lines |

`tooling/` holds tool and process docs; use `guide` or `reference` as fits.

## Article Structure

    ---
    title: Payment Reconciliation
    category: reference
    scope: [billing-service]
    tags: [architecture, api, integration]
    sources:
      - repos/billing-service/src/reconcile.ts
      - repos/billing-service/README.md
    created: 2026-01-14
    updated: 2026-03-02
    confidence: verified
    ---

    # Payment Reconciliation

    > One-sentence summary for agent quick-scan.

    ## Key Facts
    - The most important things to know, each linked to its source
    - An agent reading for orientation stops here — keep under 20 lines

    ## Details
    Deeper explanation, subsections as needed.

    ## Gotchas
    - Hard-won lessons: bug patterns, integration surprises, traps
    - Each links to the session or note that discovered it

    ## Related
    - [Other Article](../operations/other-article.md) — how it relates

## Writing Guidelines

1. **Link, don't copy.** Distil the key takeaways and link back to the source.
   If a source is a 200-line document, the wiki holds the 3 things you need to
   know and a path.
2. **Key Facts is the stop-point.** Frontmatter plus Key Facts should orient a
   reader without going further. Under 20 lines.
3. **Gotchas earn their keep.** This is where operational knowledge that would
   otherwise be lost in progress reports lives. A trap that cost someone an hour
   belongs here — it is the highest-value section in the file.
4. **Standard markdown links.** `[Title](relative-path.md)` works on GitHub and
   in editors. Same directory: `[Other](other.md)`. Across:
   `[Other](../operations/other.md)`.
5. **Sources drive staleness.** `sources:` paths are relative to the governance
   root. The index build marks an article STALE when a source has a git commit
   newer than `updated:`. Listing real source paths is what keeps the wiki
   honest — an article with no real sources can never be flagged, so it rots
   silently while looking current.

## Tag Vocabulary

Tags are how articles get found. A controlled list beats free-form tagging,
because synonyms (`db` / `database` / `postgres`) fragment the index so nothing
surfaces reliably.

**This is a starter set — replace the domain rows with your own.** The
Architecture, Governance and Ops rows are generic and worth keeping whatever you
are building.

| Domain | Tags |
|--------|------|
| _your domain_ | _replace: the 5-10 nouns your team actually says out loud_ |
| _your domain_ | _a second row if one is not enough_ |
| Architecture | `architecture`, `data-model`, `api`, `integration`, `performance` |
| Governance | `governance`, `agents`, `hooks`, `skills`, `onboarding`, `access-control` |
| Ops | `bootstrap`, `ci`, `deployment`, `git-workflow`, `secrets`, `incident` |

Add a tag when you write the *second* article needing it, not the first. A tag
with one article is a title; a tag with none is noise.

## Gotchas

- **Frontmatter must be the first thing in the file.** A leading blank line or
  comment before the opening `---` means the block is not parsed, and every
  field silently falls back to a default rather than erroring.
- **A `**Category**:` bold-markdown header is not frontmatter.** It parses as
  *no frontmatter at all*. If your index shows every article as
  `uncategorized`, or links render as `unknown/unknown.md`, this is why.
- **`updated:` is not automatic.** Bump it when you revise an article, or
  staleness detection reads the wrong baseline. Do not bump it without reading
  the changed sources — that clears the flag while leaving the article wrong,
  which is worse than leaving it flagged.
- **Generated files are not articles.** `INDEX.md`, `STALENESS.md`, `USAGE.md`,
  `schema.md` and `README.md` are skipped by the indexer. Never hand-edit the
  generated ones; the next build overwrites them.
