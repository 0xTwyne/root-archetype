# Agent Roles & Engineering Standards

**Category**: governance

The 6-section role schema, instruction budget, and harness patterns for designing agents.

## Summary

Agent roles live in `agents/roles/` (`lead-developer.md`, `research-engineer.md`, `safety-reviewer.md`) and follow a 6-section schema: Mission, Use This Role When, Inputs Required, Outputs, Workflow, Guardrails. Role files are engine-neutral — no Claude- or Codex-specific language. Shared policy lives in `agents/shared/` (`OPERATING_CONSTRAINTS.md`, `ENGINEERING_STANDARDS.md`, `WORKFLOWS.md`) and is inherited by every role; role files reference shared policy and add only role-specific overlay.

Engineering standards enforce instruction budget awareness: target ≤400 words of essential-toolchain instructions per agent file. Include only commands not discoverable from the repo (build, test, lint), toolchain requirements (`uv` vs `pip`, `pnpm` vs `npm`), and constraints that violate common conventions. Exclude codebase overviews, style guides, and architecture descriptions — agents explore better than they parse, and verbose context inflates inference cost ~20% without improving outcomes.

Harness patterns inform role design: prefer CLI wrappers over MCP servers for well-known services (GitHub, Linear, Docker, Jira) — fewer moving parts, transparent failure modes. Use sub-agents for context isolation, not role specialization. PostStop verification hooks validate builds before an agent declares done (exit 0 = silent ack, exit 2 = re-engage). Two-layer context compression — pattern-based stripping upstream + LLM summarization downstream — gives 7-11% additional savings beyond either alone.

## Key Points

- 3 starter roles in `agents/roles/`: `lead-developer`, `research-engineer`, `safety-reviewer`
- 6-section schema: Mission, Use This Role When, Inputs Required, Outputs, Workflow, Guardrails
- Role files are engine-neutral — no engine-specific language
- Shared policy: `agents/shared/OPERATING_CONSTRAINTS.md`, `ENGINEERING_STANDARDS.md`, `WORKFLOWS.md`
- Instruction budget target: ≤400 words of essential-toolchain content per agent file
- Include only: build/test commands, toolchain requirements, constraints that violate convention
- Exclude: codebase overviews, style guides, architecture descriptions (let agents explore)
- Prefer CLI wrappers over MCP servers for well-known services
- Sub-agents for context isolation, not role specialization
- PostStop verification hook: exit 0 silent, exit 2 re-engage
- Two-layer context compression: pattern-based stripping + LLM summarization

## See Also

- [`agents/roles/`](../../agents/roles/) — the 3 starter roles
- [`agents/shared/OPERATING_CONSTRAINTS.md`](../../agents/shared/OPERATING_CONSTRAINTS.md) — cross-role operating constraints
- [`agents/shared/ENGINEERING_STANDARDS.md`](../../agents/shared/ENGINEERING_STANDARDS.md) — instruction-budget standards
- [`agents/shared/WORKFLOWS.md`](../../agents/shared/WORKFLOWS.md) — shared workflow conventions
- [`scripts/validate/validate_agents_structure.py`](../../scripts/validate/validate_agents_structure.py) — 6-section schema validator
