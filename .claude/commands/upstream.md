# /upstream — Contribute Instance Changes to Archetype

Distill governance improvements from this root repo instance and submit them as a PR to root-archetype for maintainer review.

## Usage

- `/upstream` — Interactive: detect recent changes and guide through upstreaming
- `/upstream <file> [file ...]` — Upstream specific files
- `/upstream --dry-run` — Preview what would be extracted

## Steps

1. Check for `.archetype-manifest.json`. If missing, run `scripts/upstream/retroactive-manifest.sh` to create one.
2. Ask the user what they want to upstream, or detect candidates from recent commits touching portable paths.
3. Run `scripts/upstream/distill.sh` with the relevant files (or all portable paths).
4. Show the user:
   - Which files were identified as changed or new
   - Any contaminated files that need manual cleanup
   - The sanitized diffs for review
5. Show the generated handoff document draft and ask for any additions.
6. On user confirmation, run `scripts/upstream/submit-pr.sh` to create the PR.

## Notes

- The archetype must remain **project-agnostic**. The distill engine reverse-templates project-specific values back to `{{PLACEHOLDERS}}` and blocks contaminated files.
- Templated files (CLAUDE.md, README.md, SPEC.md, nightshift.yaml) get reverse-templated automatically.
- Other portable files (scripts, agents, swarm) are checked for contamination but not reverse-templated.
- The handoff document is placed in `handoffs/active/` in the archetype for independent maintainer review.
