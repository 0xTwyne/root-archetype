---
name: find-skills
description: Discover and install agent skills from the open ecosystem using npx skills. Use when user asks "find a skill for X", "is there a skill that can...", "how do I add a skill", "search skills", or wants to extend capabilities with community skills. Do NOT use when user asks about already-installed skills or wants to create a new skill (use new-skill instead).
---

# Find Skills

Discover and install skills from the open ecosystem via the `skills` CLI tool.

## Prerequisites

This skill requires `npx` (included with Node.js). Run `scripts/check-npx.sh` to verify availability.

If npx is not available:
1. Inform the user that skill discovery requires Node.js/npm
2. Suggest: `npm install -g npx` or install Node.js from https://nodejs.org
3. Offer to help directly with the user's underlying need instead

## Commands

### `npx skills find <query>`
Search the skills ecosystem for matching skills.

### `npx skills add <package>`
Install a skill from the ecosystem into the project.

### `npx skills list`
List currently installed ecosystem skills.

### `npx skills init`
Initialize skill support in a project that doesn't have it yet.

## Workflow

1. Run `scripts/check-npx.sh` to verify npx is available
2. If available: run `npx skills find "<user's query>"` to search
3. Present results with descriptions so the user can choose
4. If user selects one: run `npx skills add <package>` to install
5. If no results: offer to help directly or suggest refining the search

### Fallback (no npx)

If npx is not installed:
- Explain what skills discovery would provide
- Offer to help with the user's underlying need using existing capabilities
- Suggest installing Node.js for future skill discovery

## Agent-Discoverable Documentation

When this skill is installed, agents in this project can:
- Search the open skills ecosystem for specialized capabilities
- Install community-maintained skills that follow the Agent Skills standard
- List what ecosystem skills are currently available

This complements the project's built-in skills (listed in `.claude/skills/`) with community-contributed capabilities.

## Gotchas

- `npx skills` requires network access — will fail in air-gapped environments
- Ecosystem skills install into the project, not globally — they're scoped to this repo
- Always review a skill's source before installing — community skills are not audited by this project's governance
- The `skills` package version should be >=1.4.5 for full feature support
- If `npx` hangs, it may be prompting to install the package — run `npm install -g skills` first to avoid the prompt
