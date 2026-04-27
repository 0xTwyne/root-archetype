# Documentation & Governance Hygiene

**Category**: governance

`AGENT.md` / README conventions, knowledge-base linting, and drift detection.

## Summary

Documentation reflects the engine-neutral architecture: `AGENT.md` is primary; `CLAUDE.md` and `CODEX.md` are thin pointers that wire the engine. `README.md` covers Quick Start, Repository Structure, Hooks, Skills, Knowledge Management, Security, and Validation. `local/README.md` documents personal customization (gitignored skills, hooks, notes, config). `scripts/hooks/README.md` lists every hook with default/optional status and the steps to enable it. The `docs/guides/` directory holds longer-form guides on specific topics (security, skills engineering, secrets backend integration).

Knowledge-base linting (`agents/skills/project-wiki/scripts/lint_wiki.py`) enforces governance hygiene with five passes: orphan detection (handoffs not referenced by any index), stale entries (files unchanged past threshold days), contradictory status (status field vs. directory location), un-actioned intake (research intake without follow-up handoffs), missing cross-references (markdown links to non-existent files). Passes skip gracefully if prerequisites are missing — the linter never blocks a fresh instance from working.

Drift validators (`validate_document_drift.py`, `validate_claude_md_consistency.py`, `validate_agents_structure.py`, `validate_agents_references.py`, `validate_skills.py`) watch structural files and alert on changes. Together with `validate_hooks_lock.sh`, they form a CI-friendly hygiene battery you can run before merging governance changes.

## Key Points

- `AGENT.md` is the primary instructions file; `CLAUDE.md` / `CODEX.md` are thin engine pointers
- `README.md` covers Quick Start, Structure, Hooks, Skills, Knowledge, Security, Validation
- `local/README.md` documents per-user customization (everything under `local/*` is gitignored)
- `scripts/hooks/README.md` documents every hook with default/optional status and enable steps
- `docs/guides/` holds longer-form topic guides (security, skills engineering, secrets backends)
- `lint_wiki.py` runs 5 passes: orphan, stale, contradiction, un-actioned, missing cross-ref
- Linter passes skip gracefully when prerequisites missing — never blocks a fresh instance
- Drift validators in `scripts/validate/` form a hygiene battery for CI
- README templates use `{{PLACEHOLDERS}}` substituted at init time

## See Also

- [`AGENT.md`](../../AGENT.md) — primary instructions file
- [`README.md`](../../README.md) — top-level project documentation
- [`local/README.md`](../../local/README.md) — personal customization guide
- [`scripts/hooks/README.md`](../../scripts/hooks/README.md) — per-hook reference
- [`docs/guides/`](../../docs/guides/) — longer-form topic guides
- [`agents/skills/project-wiki/scripts/lint_wiki.py`](../../agents/skills/project-wiki/scripts/lint_wiki.py) — KB linter
- [`scripts/validate/`](../../scripts/validate/) — drift validators
