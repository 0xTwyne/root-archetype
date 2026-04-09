# CLI Wrapper Templates

Templates for thin CLI wrapper scripts. Use these instead of MCP servers when the external service has a mature CLI with structured output.

See `references/tool-integration-decision-matrix.md` for the full scoring rubric on when to use CLI wrappers vs MCP servers vs native tools.

## Wrapper Structure Convention

Each wrapper follows this pattern:

1. **Shebang + strict mode**: `#!/bin/bash` with `set -euo pipefail`
2. **Usage examples as comments**: 5-6 documented invocations agents can learn from
3. **Structured output**: Always use `--json` or equivalent for machine-parseable output
4. **Error handling**: Meaningful exit codes and stderr messages

## When to Use

- Service has a stable CLI with `--json` output
- CLI commands are in model training data (GitHub, Docker, cloud CLIs)
- No persistent session/auth state needed between calls
- You want `grep`/`jq` composability

## When NOT to Use

- Novel internal APIs without CLI tooling
- Services requiring stateful sessions (databases, browsers)
- Complex structured I/O where MCP schema validation adds value

## Templates

- `gh-wrapper.sh.template` — GitHub CLI wrapper with structured JSON output
