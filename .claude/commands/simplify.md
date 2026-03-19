# /simplify — Code Simplification Review

Review recently changed code for clarity, complexity, and consistency issues, then apply improvements.

## Usage

- `/simplify` — Review all recently modified files (from git diff)
- `/simplify <file> [file ...]` — Review specific files

## Steps

1. If `$ARGUMENTS` provided, review those files. Otherwise, identify recently modified files from `git diff` and `git diff --cached`.
2. Read each file and analyze for:
   - Cyclomatic complexity > 10
   - Nested ternaries, open-ended while loops, recursion
   - Naming clarity, structural consistency
3. Present findings and proposed changes to user for approval.
4. Apply approved changes.
5. Use the rationale template from `.claude/skills/simplify/assets/rationale-template.md` for commit messages.

## Notes

- Follow the target project's CLAUDE.md for language conventions
- Never combine simplification with behavioral changes
- Clarity over brevity — always
