# Knowledge Compilation Pipeline

**Category**: architecture

Two-tier flow from per-user logs and notes into a shared, curated knowledge base.

## Summary

Knowledge management in root-archetype is two-tier: per-user append-only streams (logs, notes, research intake) flow into compiled shared artifacts (master wiki, curated research). No two users write to the same file, eliminating merge conflicts and enabling async collaboration. Compilation is part-mechanical (shell), part-LLM (skill).

The mechanical half is `scripts/utils/generate-handoff-index.sh` — scans every handoff doc and writes `notes/handoffs/INDEX.md` on every session-end. The LLM half is the `project-wiki` skill's `compile` operation: `compile_sources.py` lists files newer than `.last_compile`; an agent reads them, clusters by topic, synthesizes pages into `knowledge/wiki/`. Research intake mirrors this — per-user `notes/<user>/research/` is curated into `knowledge/research/` during master compile.

Optional log repo (`--log-repo` at init) physically separates logs/notes into `repos/<project>-logs/`. Master compilation becomes doubly incremental: skips files older than `.last_compile` AND files already listed in `.promoted-sources`. Use `--full` to reset both.

## Key Points

- Per-user append-only model: `logs/progress/<user>/`, `notes/<user>/`, `logs/audit/<user>/` — no cross-user writes
- Two compilation halves: mechanical (handoff `INDEX.md`) + LLM (`project-wiki` skill → `knowledge/wiki/`)
- `.last_compile` timestamp gates staleness; `compile_sources.py` lists newer-than-threshold sources
- `--log-repo` at init splits logs into `repos/<project>-logs/`; default is single-repo
- `research-intake` skill writes to `notes/<user>/research/`; maintainers promote to `knowledge/research/` during master compile
- `.promoted-sources` skips already-merged sources on subsequent runs; `--full` overrides
- Session-start hook detects stale wiki state and prompts a recompile

## See Also

- [`agents/skills/project-wiki/SKILL.md`](../../agents/skills/project-wiki/SKILL.md) — full compile workflow
- [`agents/skills/research-intake/SKILL.md`](../../agents/skills/research-intake/SKILL.md) — structured research ingestion
- [`scripts/utils/generate-handoff-index.sh`](../../scripts/utils/generate-handoff-index.sh) — mechanical index generator
- [`agents/skills/project-wiki/scripts/compile_sources.py`](../../agents/skills/project-wiki/scripts/compile_sources.py) — manifest scanner
- [`taxonomy.yaml`](../../knowledge/taxonomy.yaml) — categories and confidence levels for compiled pages
