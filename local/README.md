# Local — Instance Customization

This directory is **gitignored**. Use it for per-machine customization
that should not be shared across clones.

## Structure

```
local/
├── skills/     # Personal skill definitions
├── hooks/      # Personal hook overrides
├── notes/      # Personal scratchpad
└── config/     # Machine-specific configuration
```

## Usage

- **Skills**: Drop a skill folder here. Claude Code discovers skills in
  both `.claude/skills/` (tracked) and `local/skills/` (personal).
- **Hooks**: Override or extend hook behavior without modifying tracked files.
- **Notes**: Scratch space for ideas, experiments, drafts.
- **Config**: Machine-specific env vars, paths, tool configs.

## Discovery

Personal skills in `local/skills/` follow the same structure as
`.claude/skills/` — each needs a `SKILL.md` with YAML frontmatter.
They are NOT validated by `scripts/validate/validate_skills.py`
(that only checks tracked skills).
