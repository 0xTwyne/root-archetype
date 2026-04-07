# Engineering Standards

## Code Invariants

- Use typed boundaries for external data
- Use enums/constants, not ad hoc strings
- Feature-flag optional or expensive components
- Log exceptions with context (never silent `except: pass`)
- Thread-safe state updates for shared mutable state

## Numeric Parameter Policy

Every numeric value is classified as:
- **tunable**: runtime behavior control — typed config/dataclass + env override
- **invariant**: stable semantic limit — subsystem-local constant

Do NOT consolidate all numbers in one file; preserve subsystem ownership.

## Instruction Budget Policy

Every instruction in agent files is classified as:
- **essential-toolchain**: build commands, test runners, required toolchain (e.g., `uv`, specific pytest flags) that the agent cannot discover from the repo
- **nice-to-have**: style guides, architecture overviews, coding preferences

Target: agent files ≤400 words of essential-toolchain instructions. Overviews and style guides are excluded — agents explore better than they parse descriptions. Every instruction consumes model attention budget; verbose files increase inference cost by 20%+ without improving success rates.

## Change Style

- One concern per change
- Reuse existing modules before adding helpers
- Follow existing project layout
- PRs adding numerics must include one-line classification

## Verification Minimum

1. Syntax check for modified Python files
2. Run targeted tests for touched behavior
3. Confirm feature-flag behavior
4. Update docs when behavior changes
