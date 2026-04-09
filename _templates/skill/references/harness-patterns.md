# Harness Engineering Patterns

Portable patterns for configuring Claude Code agent harnesses. Derived from empirical research on coding agent performance.

---

## Pattern 1: CLI > MCP for Well-Known Services

**When**: External service has a mature CLI with structured output (GitHub, Docker, cloud CLIs).
**When NOT**: Novel/internal services without CLI; stateful sessions; browser automation.

Build a thin CLI wrapper script with documented usage examples instead of connecting a full MCP server. MCP tool definitions consume thousands of tokens per server. CLI commands are already in model training data and preserve `grep`/`jq` composability.

> Evidence: HumanLayer TerminalBench-2 — rank delta ~28 from harness alone.

---

## Pattern 2: Agent File Sizing

**When**: Writing or reviewing CLAUDE.md, AGENTS.md, or similar agent instruction files.
**When NOT**: Documentation for humans (README, docs/).

Target ≤400 words of essential-toolchain instructions. Include only: build/test commands not discoverable from the repo, toolchain requirements, and constraints that violate common conventions. Exclude: codebase overviews, style guides (unless they cause CI failures), and architecture descriptions.

> Evidence: ETH Zurich (arXiv:2602.11988) — context files increase cost 20%+ without improving success.

---

## Pattern 3: Sub-Agent Context Isolation

**When**: A task produces large intermediate outputs that could degrade parent context.
**When NOT**: Simple sequential tasks where outputs are small.

Use sub-agents for context isolation, not role specialization. The parent sees only the condensed result, not intermediate tool calls. Sub-agents should return condensed answers with `filepath:line` citations.

**Anti-pattern**: Role-based sub-agents ("frontend engineer", "backend engineer") consistently fail — a model role-playing a persona does not gain expertise.

> Evidence: Chroma "Context Rot" research — performance degrades with input length.

---

## Pattern 4: PostStop Verification Hook

**When**: The project has a build/lint/typecheck step that should pass before work is considered done.
**When NOT**: Projects without automated checks; exploratory/research sessions.

Run build/lint/typecheck as a PostStop hook. Exit 0 = silent success (no context injection). Exit 2 = re-engage agent with error output. Only failures inject context, keeping the success path silent.

See `_templates/hooks/poststop_verify.sh.template` for a ready-to-use template.

> Evidence: Agents frequently declare "done" with broken builds; gate catches this before human review.

---

## Pattern 5: Two-Layer Context Compression

**When**: Long-running sessions with many tool outputs accumulating.
**When NOT**: Short sessions; sessions where full tool output is needed for audit trails.

Layer 1 (pattern-based): Strip boilerplate from known tool outputs (pytest collection lines, git diff headers). Extract key facts: failures, changed files, error messages.

Layer 2 (LLM summarization): Compress conversation history at configurable trigger thresholds for narrative/reasoning content.

> Evidence: "The Complexity Trap" (arXiv:2508.21433) — observation masking matches LLM summarization at 50% cost reduction; hybrid gives 7-11% further savings.

---

## Pattern 6: Instruction Budget Awareness

**When**: Maintaining any agent instruction file.
**When NOT**: N/A — always applicable.

Every instruction consumes model attention budget. Classify each instruction as:
- **essential-toolchain**: agent will fail without it; not discoverable from the repo
- **nice-to-have**: improves behavior but is discoverable or optional

Budget ceiling: if instruction tokens exceed 20% of total input tokens, the file is likely net-negative. Do NOT use `/init` or auto-generation — LLM-generated files consistently underperform manually curated minimal files.

> Evidence: ETH Zurich (arXiv:2602.11988) — verbose instructions increase cost without improving success.
