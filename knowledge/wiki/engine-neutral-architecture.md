# Engine-Neutral Architecture

**Category**: architecture

How the same governance scaffold runs under Claude Code, Codex, or any future engine.

## Summary

Root-archetype is engine-agnostic. Engine-specific wiring is separated from core content through a template-based generation pattern: only engine-neutral content is tracked in git; generated adapter files (`settings.json`, `CLAUDE.md`, `.claude/skills/`) are gitignored and produced at init time per installation.

`AGENT.md` is the single source of truth for agent instructions. Engine-specific files (`CLAUDE.md` for Claude Code, `CODEX.md` for Codex/OpenAI) are thin pointers that reference `AGENT.md` and add only engine-specific wiring. Skills follow the same pattern: canonical `SKILL.md` lives in `agents/skills/`; thin engine wrappers under `.claude/skills/` exist solely so Claude Code can discover the skill.

`init-project.sh --engine <name>` reads templates from `agents/engines/<engine>/` and produces engine-specific files locally. The committed tree stays engine-neutral; engine adapters can evolve independently.

## Key Points

- `AGENT.md` is engine-neutral and primary; `CLAUDE.md` / `CODEX.md` are thin pointers with engine wiring only
- Adapter files (`settings.json`, `.claude/skills/`, `CLAUDE.md`, `CODEX.md`) are generated at init time and gitignored at rest
- Skills live once in `agents/skills/`; `.claude/skills/` holds engine-specific discovery wrappers
- Template placeholders use `{{DOUBLE_BRACES}}`; `init-project.sh` substitutes `{{PROJECT_NAME}}` and `{{PROJECT_ROOT}}`
- Engine-specific language is forbidden in `AGENT.md` and `agents/roles/` files — keep those engine-neutral
- Adding a new engine = drop a template directory under `agents/engines/<engine>/`; no core changes needed

## See Also

- [`AGENT.md`](../../AGENT.md) — the engine-neutral instructions file every engine reads
- [`CLAUDE.md`](../../CLAUDE.md) and [`CODEX.md`](../../CODEX.md) — example thin pointers
- [`init-project.sh`](../../init-project.sh) — scaffolding entry point with `--engine` flag
- [`agents/engines/`](../../agents/engines/) — per-engine template directories
- [Claude Code docs](https://docs.claude.com/en/docs/claude-code) — Claude-specific engine reference
