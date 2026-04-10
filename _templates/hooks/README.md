# Hook Templates

Templates for Claude Code tool-use hooks. Hooks run automatically before or after tool calls, providing guardrails and verification without consuming agent context on success.

## Trigger Types

| Trigger | When | Use For |
|---------|------|---------|
| `PreToolUse` | Before a tool executes | Blocking unsafe operations, path validation |
| `PostToolUse` | After a tool executes | Output filtering, logging |
| `Stop` | When agent signals completion | Final verification gates |

## Exit Code Semantics

| Code | Meaning | Agent Sees |
|------|---------|------------|
| `0` | Success — silent | Nothing (no context consumed) |
| `2` | Failure — re-engage | Hook's stdout/stderr (agent retries) |

Exit 0 on success is critical: silent success keeps agent context clean. Only failures inject text.

## Installation

1. Copy template to `scripts/hooks/` in your project
2. Replace `{{placeholders}}` with project-specific commands
3. Register in `.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      { "command": "bash scripts/hooks/poststop_verify.sh" }
    ]
  }
}
```

## Templates

- `poststop_verify.sh.template` — Build/lint/typecheck gate on session completion
