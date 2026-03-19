# Commit Rationale Template

Use this template for simplification commit messages.

## Format

```
<Subject>: [Brief summary, e.g., "Refactor API handler for clarity"]

Rationale:
* The Problem: [Complexity, security risk, or stylistic issue found]
* The Fix: [Refactoring technique applied]
* Safety Check: [Confirmation of functionality preservation]
* Complexity Delta: [Before score] -> [After score]

Before/After:
> Old: [Summary of previous implementation]
> New: [Summary of simplified implementation]
```

## Example

```
Refactor: simplify request validation pipeline

Rationale:
* The Problem: validateRequest() had cyclomatic complexity 14 with nested conditionals for auth, rate limiting, and input parsing
* The Fix: Extracted three focused validators (validateAuth, checkRateLimit, parseInput) composed in a pipeline
* Safety Check: All 47 existing tests pass; added 3 edge-case tests for the extracted functions
* Complexity Delta: 14 -> 4 (main), 3, 3, 4 (extracted)

Before/After:
> Old: Single 85-line function with 6 levels of nesting
> New: 4 functions averaging 20 lines, max nesting depth 2
```
