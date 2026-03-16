# Upstream Contribution Skill

## Description

Extract governance improvements from a live root repo instance, sanitize them of project-specific references, and submit as a PR to root-archetype for maintainer review.

## Commands

### `/upstream`
Interactive mode: detect recent governance changes and guide the user through upstreaming.

### `/upstream <file> [file ...]`
Upstream specific files to root-archetype.

### `/upstream --dry-run`
Preview what files differ from the archetype without staging anything.

## Workflow

1. **Manifest check**: Ensure `.archetype-manifest.json` exists (create with `retroactive-manifest.sh` if needed)
2. **Detect changes**: Compare instance portable paths against archetype
3. **Reverse-template**: Replace project-specific values with `{{PLACEHOLDERS}}`
4. **Contamination check**: Block files that still contain project-specific references
5. **Stage**: Clean files go to a staging directory
6. **Handoff**: Generate review document for archetype maintainer
7. **Submit**: Create branch, commit, push, and open PR against root-archetype

## Implementation

The upstream pipeline lives in `scripts/upstream/`:
- `retroactive-manifest.sh` — Generate manifest for pre-existing instances
- `distill.sh` — Core extraction and sanitization engine
- `submit-pr.sh` — Branch, commit, push, and PR creation

The manifest (`.archetype-manifest.json`) tracks:
- Archetype origin path and version
- Template values used during init (PROJECT_NAME, PROJECT_ROOT)
- Which paths are portable (governance) vs templated

## Key Concepts

- **Portable paths**: Files that are copied verbatim from archetype to instance (scripts, agents, swarm)
- **Templated files**: Files where `{{PLACEHOLDERS}}` are replaced during init (CLAUDE.md, README.md)
- **Reverse-templating**: Replacing concrete values back to placeholders for upstream
- **Contamination**: Project-specific references that survive reverse-templating — these must be manually cleaned
