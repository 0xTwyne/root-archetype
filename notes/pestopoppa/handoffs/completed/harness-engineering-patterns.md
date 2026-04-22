# Harness Engineering Patterns

**Status**: completed
**Created**: 2026-04-06 (via research intake deep-dive)
**Categories**: agent_architecture, governance
**Origin**: intake-271 (HumanLayer), intake-272 (ETH Zurich), intake-273 (Chroma), intake-274 (Complexity Trap)

## Objective

Codify portable harness engineering patterns for any Claude Code project using root-archetype. These patterns are derived from empirical research and practitioner experience with coding agents, distilled to be project-agnostic.

---

## Patterns

### 1. CLI > MCP for Well-Known Services

**When**: The external service has a mature CLI with structured output (GitHub, Linear, Docker, Jira, cloud CLIs).

**Pattern**: Build a thin CLI wrapper script with 5-6 documented usage examples in `CLAUDE.md` instead of connecting a full MCP server.

**Why**: MCP tool definitions consume thousands of tokens per server. CLI commands are already in model training data. Preserves `grep`/`jq` composability.

**When NOT to use**: Novel or internal services without CLI tooling; services requiring stateful sessions; browser automation.

### 2. Agent File Sizing

**Target**: Agent files (CLAUDE.md, AGENTS.md) should contain ≤400 words of essential-toolchain instructions.

**Include only**:
- Build/test commands not discoverable from the repo (specific runners, flags, environment setup)
- Toolchain requirements (`uv` vs `pip`, `pnpm` vs `npm`, required pre-commit hooks)
- Constraints that violate common conventions (e.g., "do not modify files in `vendor/`")

**Exclude**:
- Codebase overviews and directory listings — agents explore better than they parse descriptions
- Style guides — unless they encode hard constraints that cause CI failures
- Architecture descriptions — agents discover structure from imports and call graphs

**Evidence**: ETH Zurich (arXiv:2602.11988) found context files increase inference cost by 20%+ without improving success rates. Codebase overviews do not reduce the number of steps to first interact with relevant files. Human-written minimal files outperform LLM-generated verbose files.

### 3. Sub-Agent Context Isolation

**Pattern**: Use sub-agents for **context isolation**, not role specialization. The parent sees only the condensed result, not intermediate tool calls.

**Anti-pattern**: Role-based sub-agents ("frontend engineer", "backend engineer") — these consistently fail in practice. A single model role-playing a persona does not gain expertise.

**Why it works**: Every intermediate tool output is a potential distractor that compounds performance degradation at longer context lengths (Chroma "Context Rot" research). Sub-agent isolation prevents this accumulation.

**Best practice**: Sub-agents should return condensed answers with `filepath:line` citations. Parent thread stays focused on high-level coordination.

### 4. PostStop Verification Hook

**Pattern**: Run build/lint/typecheck as a PostToolUse or PostStop hook. Exit code 0 = silent success (no context injection). Exit code 2 = re-engage agent with error output.

**Why**: Agents frequently declare "done" with broken builds. A verification gate catches this before the human reviews. Success is silent — only failures inject context.

**Example** (bash hook):
```bash
#!/bin/bash
set -euo pipefail
# Run in parallel, collect failures
failures=""
npm run typecheck 2>&1 || failures+="typecheck "
npm run lint 2>&1 || failures+="lint "
if [ -n "$failures" ]; then
  echo "FAILED: $failures"
  exit 2  # Re-engage agent
fi
exit 0  # Silent success
```

### 5. Two-Layer Context Compression

**Pattern**: Compress tool outputs with pattern-based rules first (upstream), then apply LLM-based conversation summarization second (downstream).

**Layer 1 (pattern-based)**: Strip boilerplate from known tool outputs (pytest collection lines, git diff index headers, ls formatting). Extract key facts: failures, changed files, error messages.

**Layer 2 (LLM summarization)**: Compress conversation history at configurable trigger thresholds. This handles the narrative/reasoning content that pattern matching can't.

**Evidence**: "The Complexity Trap" (arXiv:2508.21433) shows simple observation masking (stripping old tool outputs) matches LLM summarization at 50% cost reduction. The hybrid approach (both layers) provides 7-11% further savings. This two-layer design is near-optimal.

### 6. Instruction Budget Awareness

**Principle**: Every instruction in agent files consumes model attention budget. Verbose instructions increase inference cost by 20%+ without improving task success rates.

**Classification**: Every instruction should be classified as:
- **essential-toolchain**: cannot be discovered from the repo; agent will fail without it
- **nice-to-have**: improves agent behavior but is discoverable or optional

**Budget ceiling**: If instruction tokens exceed 20% of total input tokens, the agent file is likely net-negative. Measure and monitor.

**Corollary**: Do NOT use `/init` or auto-generation to create agent files. LLM-generated files consistently underperform manually curated minimal files.

---

## Anti-Patterns

1. **Pre-emptive harness design**: Adding configuration before encountering actual failures. Only configure when agents repeatedly fail at a specific pattern.
2. **MCP server hoarding**: Installing many MCP servers "just in case" floods the tool definition space and wastes context.
3. **Micro-managed tool access**: Restricting which sub-agents can access which tools causes "tool thrash" — agents waste turns trying to accomplish tasks without the right tools.
4. **Full test suites at session end**: Running a 5+ minute full test suite floods context with irrelevant pass/fail output. Run targeted tests during development; full suite in CI.

---

## Outstanding Tasks

- [x] Implement patterns as skill templates in `_templates/skill/` — ✅ 2026-04-09 `_templates/skill/references/harness-patterns.md`
- [x] Add PostStop hook example to `_templates/hooks/` — ✅ 2026-04-09 `_templates/hooks/poststop_verify.sh.template`
- [x] Document CLI wrapper pattern with examples for common services (GitHub CLI, Docker CLI) — ✅ 2026-04-09 `_templates/cli-wrappers/`
- [x] Add instruction budget guidance to `agents/shared/ENGINEERING_STANDARDS.md` — ✅ Already present in ENGINEERING_STANDARDS.md lines 19-25
- [x] Create decision matrix: CLI vs MCP vs native tool (scoring rubric) — ✅ 2026-04-09 `_templates/skill/references/tool-integration-decision-matrix.md`

---

## Research Sources

| Source | Key Finding |
|--------|-------------|
| HumanLayer "Skill Issue" blog (2026-03-12) | TerminalBench-2 rank delta ~28 from harness alone; CLI > MCP; role sub-agents fail |
| ETH Zurich arXiv:2602.11988 | Context files reduce success rates, +20% cost; overviews don't help navigation |
| Chroma "Context Rot" (2025-07-14) | Performance degrades with input length; low-similarity content degrades fastest |
| "The Complexity Trap" arXiv:2508.21433 | Observation masking matches LLM summarization; hybrid gives 7-11% further savings |
