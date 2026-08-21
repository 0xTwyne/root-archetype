# Knowledge Wiki

The project's compiled knowledge, kept in the same repo as the per-user streams
it is compiled from.

Start at [INDEX.md](INDEX.md). It lists every article with its category, tags and
freshness, and ends with a scope lookup — which articles cover which repo.

## What goes here

Distilled, reusable knowledge with more than one reader and a life longer than
one session: how a subsystem actually works, why a convention exists, a trap
that already cost someone an afternoon.

What does **not** go here:

| Instead of the wiki | Use |
|---|---|
| What happened this session | `logs/progress/<user>/` |
| Work being handed to someone | `notes/<user>/handoffs/` |
| Your own always-on reminders | `notes/<user>/facts.md` (keep under 80 lines) |
| Raw source material | link to it from an article's `sources:` |

The distinction that matters: progress logs are *what happened*, the wiki is
*what is true*. A finding only becomes wiki-worthy once it will still be
relevant to someone who was not there.

## Layout

Articles live in a category directory. The category in the frontmatter and the
directory must agree — see [schema.md](schema.md).

```
wiki/
├── schema.md        frontmatter spec, categories, tag vocabulary
├── INDEX.md         generated — catalog + scope lookup
├── STALENESS.md     generated — articles whose sources moved on
├── concepts/        domain concepts and mechanics
├── repos/           per-repo architecture and conventions
├── operations/      procedures, onboarding, governance
├── research/        findings, methodology, data pipelines
├── incidents/       post-incident knowledge
└── tooling/         tool and process documentation
```

## Working with it

```bash
/project-wiki                      # query
/project-wiki create <topic>       # scaffold one article
/project-wiki compile              # synthesize from logs and handoffs
/project-wiki refresh              # update articles whose sources changed
bash scripts/build-indexes.sh      # regenerate INDEX.md and STALENESS.md
```

`INDEX.md` and `STALENESS.md` are generated. Never hand-edit them — the next
build silently overwrites your changes.

## Keeping it honest

An article is marked STALE when a path in its `sources:` has a git commit newer
than its `updated:` date. This is the whole reason `sources:` is required: an
article without real source paths can never be flagged, so it rots while
continuing to look current.

If `INDEX.md` shows articles as `uncategorized`, or links rendering as
`unknown/unknown.md`, the frontmatter is not parsing — check that `---` is the
very first line of the file, and see the Gotchas in `schema.md`.
