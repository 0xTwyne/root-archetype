# Tool Integration Decision Matrix

Scoring rubric for choosing between CLI wrapper, MCP server, and native tool integration.

---

## Criteria

| Criterion | CLI Wrapper | MCP Server | Native Tool |
|-----------|:-----------:|:----------:|:-----------:|
| **CLI maturity** (stable CLI with `--json`) | +2 | 0 | 0 |
| **Training data** (CLI in model training corpus) | +1 | 0 | +1 |
| **Statefulness** (needs persistent session/auth) | -1 | +2 | +1 |
| **Token cost** (tool definitions in context) | +2 (zero) | -2 (thousands) | 0 |
| **Composability** (pipe, grep, jq) | +2 | -1 | 0 |
| **Schema richness** (complex structured I/O) | -1 | +2 | +1 |
| **Discoverability** (agent can learn usage from examples) | +1 | +1 | +2 |

Score range: -3 to +7 per option.

## Decision Thresholds

| Score | Decision |
|-------|----------|
| ≥ 4 | Strong fit — use this approach |
| 2-3 | Acceptable — use if no stronger alternative |
| ≤ 1 | Poor fit — choose another approach |

## Tie-Breaking Rule

When CLI wrapper and MCP server score equally: **prefer CLI wrapper**. Lower maintenance burden, zero token overhead, and CLI commands degrade gracefully (agent can read `--help`).

## Quick Decision Guide

| Service Type | Recommendation | Example |
|-------------|---------------|---------|
| Git hosting (GitHub, GitLab) | CLI wrapper | `gh` with `--json` |
| Container runtime | CLI wrapper | `docker` / `podman` |
| Cloud provider | CLI wrapper | `aws` / `gcloud` / `az` |
| Database (stateful queries) | MCP server | Postgres, Redis |
| Browser automation | MCP server | Playwright |
| Novel internal API | MCP server | Custom REST/gRPC |
| Language toolchain | Native tool | Compiler, linter, formatter |
