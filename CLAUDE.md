# Claude Code Configuration

> Primary instructions: read `AGENT.md` in this directory.
> This file contains Claude Code-specific wiring only.

## Engine Wiring

- Settings: `.claude/settings.json` — hook paths, permissions
- Skills: `.claude/skills/` — the skills themselves, tracked in git
- Commands: `.claude/commands/` — tracked in git
- Local overrides: `.claude/settings.local.json` (gitignored)

## Skill Discovery

Claude Code discovers skills via a SKILL.md under `.claude/skills/`, and that
file **is** the skill — there is no wrapper layer and no generation step. To add
or change one, edit it in place and commit. Collaborators get it on `git pull`,
with no regeneration and no session restart.

This was previously two tiers: engine-neutral content under an `agents/skills`
tree, with thin generated wrappers in a **gitignored** `.claude/skills/`. It
meant a skill committed to git reached nobody, because the generator ran only
when `.claude/skills/` was missing entirely — so anyone who had set the project
up once kept their original set forever, and pulling could not fix it.

Do not reintroduce a generated, gitignored layer under `.claude/`.

## Hooks

All hooks live in `scripts/hooks/`. Claude wiring in `.claude/settings.json`
points to those paths. See `scripts/hooks/README.md` for hook documentation.
