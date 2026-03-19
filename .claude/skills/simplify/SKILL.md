---
name: simplify
description: Review changed code for reuse, quality, and efficiency, then fix any issues found. Use when user says "simplify", "review code", "clean up", "refactor", "reduce complexity", or after completing a significant code change. Do NOT use for general code questions, debugging, or feature implementation.
---

# Code Simplification

Review recently modified code for clarity, consistency, and maintainability — then apply improvements with user approval.

## What to do

1. Identify the recently modified code sections (from git diff, staged changes, or user-specified files via `$ARGUMENTS`).
2. Analyze for complexity, clarity, and consistency issues.
3. Measure cyclomatic complexity — if a function scores above **10**, it must be refactored into smaller sub-functions.
4. Apply refinements and verify all functionality remains unchanged.
5. Present changes to the user for **manual approval** before committing.

## Rules

### Preserve functionality
Never change what the code does — only how it does it. All original features, outputs, and behaviors must remain intact.

### Structural constraints
- No recursion — use iterative solutions
- No open-ended `while` loops
- No nested ternary operators — prefer `switch` or `if/else`
- **Clarity over brevity** — explicit code beats dense one-liners

### Project-specific standards
Follow the target project's CLAUDE.md for language-specific conventions (import style, function declarations, type annotations, error handling). Do not impose conventions from other projects.

### Balance
Avoid over-simplification that creates:
- "Overly clever" solutions harder to understand than the original
- Single functions combining too many concerns
- Removal of helpful abstractions that improve organization
- Code that's harder to debug or extend

### Commit rationale
When committing, use the rationale template in `assets/rationale-template.md`. The commit message must explain **why** the change was made, not just what changed.

## Gotchas

- Always read the project's CLAUDE.md before applying language-specific conventions — what's standard in one repo may be wrong in another
- Cyclomatic complexity >10 is a refactoring trigger, not a hard error — some algorithms genuinely need branching (parsers, state machines). Use judgment.
- "Simplify" does not mean "shorten" — a 20-line function with clear intent beats a 5-line function with obscure intent
- Never combine simplification with feature changes in the same commit — reviewers can't distinguish behavioral changes from cosmetic ones
- Security-sensitive code (input sanitization, auth checks) should be simplified with extra caution — don't remove "redundant" checks that may be defense-in-depth
