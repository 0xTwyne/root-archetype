# Root-Archetype: Swarm Coordination Architecture

## Status: IN PROGRESS

## Summary

Created the `root-archetype` repository — a project-agnostic template for seeding governance root repos with built-in multi-agent swarm coordination. Inspired by Karpathy's agenthub, adapted for governed, single-machine, inference-bottlenecked environments.

## Repository

- **Location**: `/mnt/raid0/llm/root-archetype`
- **GitHub**: https://github.com/pestopoppa/root-archetype
- **Commits**: 9 (initial scaffold + cost policy + twyne-root port + contamination fix + upstream pipeline + GitNexus + template gap docs + handoff refresh + session work)
- **Files**: 83 files, ~6700 LOC

## What's Built

### Governance Primitives (synthesized from epyc-root + twyne-root)
- 11 hooks spanning 6 events (SessionStart, SessionEnd, PreToolUse, PostToolUse, UserPromptSubmit, SubagentStart)
- 2 validators (agent structure, references)
- 3 example agent roles (lead-developer, research-engineer, safety-reviewer)
- Shared policy (operating constraints, engineering standards, workflows)
- Agent logging (JSONL audit trail + analyzer)
- Session management (init, health check)
- Cost optimization policy (model tier routing, context compaction, budget controls)

### Swarm Coordination Primitive
- **Coordinator** (`swarm/coordinator.py`, ~640 LOC): SQLite-backed with WAL mode
  - Agent registration + heartbeat + stale-claim release
  - Priority work queue (not FIFO)
  - Message board (channels + threaded posts)
  - Resource locks with TTL
  - Budget enforcement per agent with ledger
- **Experiment Scheduler** (`swarm/scheduler.py`, ~340 LOC):
  - ParetoArchive with hypervolume tracking (2D exact, >2D Monte Carlo)
  - Expected Improvement scoring: frontier distance, novelty, species diversity, uncertainty
  - Re-scores all pending experiments after each validation
  - Species effectiveness tracking for MetaOptimizer feedback
- **Swarm Client** (`swarm/client.py`, ~200 LOC):
  - Thin agent library with context manager
  - Auto-heartbeat thread
  - Lock tracking and cleanup on exit

### Infrastructure
- `init-project.sh` — Seed new projects from archetype with variable substitution
- Child repo management: register, scan-agents, sync, add-dependency
- Nightshift swarm scheduler: run_wrapper.sh with --swarm flag, inference guard, nightshift.yaml
- Upstream contribution pipeline (`scripts/upstream/`): distill + reverse-template + contamination check + PR submission, with `/upstream` command and skill
- GitNexus codebase intelligence: structural code awareness via CLI/MCP, auto-indexed by `sync-repos.sh --index`
- Claude Code integration: 2 commands (`swarm.md`, `upstream.md`), 2 skills (`swarm/`, `upstream/`), settings.json

## GitHub Issues (Work Backlog)

1. [#1 Governance Synthesis](https://github.com/pestopoppa/root-archetype/issues/1) — Complete remaining governance ports
2. [#2 Swarm Hardening](https://github.com/pestopoppa/root-archetype/issues/2) — Testing, edge cases, HTTP API
3. [#3 AutoPilot as Swarm Consumer](https://github.com/pestopoppa/root-archetype/issues/3) — Restructure AutoPilot to use swarm
4. [#4 Nightshift as Swarm Scheduler](https://github.com/pestopoppa/root-archetype/issues/4) — Full swarm-mode nightshift

## Key Design Decisions

1. **SQLite-first coordinator** — No HTTP server. WAL mode handles concurrent agent access on shared filesystem.
2. **Priority queue, not FIFO** — Experiment scheduler maximizes Pareto frontier information per unit of inference time.
3. **Dumb coordinator, smart agents** — Coordinator stores data and enforces constraints. Agents make scoring decisions.
4. **Worktree isolation** — Each swarm agent gets its own git worktree. Governance hooks apply per-worktree.
5. **Umbrella PR for nightshift** — Single consolidated report per run, not N individual PRs. Risk-tiered merge policy.
6. **Cost optimization as primitive** — Model tier routing, context compaction, budget controls ship with the archetype.

### Twyne-Root Patterns Ported
- Session lifecycle hooks (start/end with identity, branch, facts cache)
- Pre-edit guard (secret scanning + log isolation + config tamper-proofing)
- Correction detection (UserPromptSubmit → agent file gap assessment)
- Ripple detection (PostToolUse → dependency map downstream warnings)
- Write-time linting (PostToolUse → repo-toolchains.json)
- Subagent context injection (SubagentStart → repo CLAUDE.md + budget visibility)
- Post-tool-use audit (session stats tracking for cost optimization)
- Hook utilities library (fail-open, block, warn, dedup, identity, facts)
- Session counters (threshold-based hook behavior)
- Maintainer permissions model (global + per-repo scopes, hard-block config)
- Secret pattern scanning (8 patterns: GitHub PAT, AWS, Anthropic, etc.)
- Direct-to-main push for logs/notes (worktree-based, no PR friction)
- Cost optimization: subagent model routing, max_turns per type, budget visibility, facts cache

## Known Issues / Implementation Debt

**Dead code:**
- `budget_ledger` table in coordinator.py: inserted into but never queried — **FIXED**: added `get_budget_history()` query method
- `_submitted_items` list in client.py: appended to but never read — **FIXED**: removed

**Concurrency:**
- Lock race condition in `acquire_lock()` — doesn't use `BEGIN IMMEDIATE` — **FIXED**: wrapped in `BEGIN IMMEDIATE` transaction
- `select_next()` not thread-safe — two callers can select same item — **FIXED**: `select_next(agent_id)` now atomically claims via coordinator

**Scaling:**
- Objective scoring not normalized in scheduler — `frontier_distance` can have arbitrary magnitude vs [0,1] bounded components — **FIXED**: sigmoid normalization `1 - exp(-x)`

**Stubs:**
- Nightshift sequential mode (run_wrapper.sh) — **FIXED**: parses yaml via `yq`, launches Claude Code per task
- Nightshift worker launch (run_wrapper.sh) — **FIXED**: spawns parallel Claude Code sessions, waits for completion

**Template gaps:**
- `init-project.sh` doesn't copy `maintainers.json` to new projects — tamper-proofing hook silently degrades
- No `{{MAINTAINER_EMAIL}}` template variable — seeded projects can't auto-populate maintainer identity

**Documentation drift:**
- CLAUDE.md listed 4 validators, only 2 exist (fixed 2026-03-14)

## Contamination Audit — PASSED

Full audit found 7 instances of project-specific material. All fixed in commit `06e1b31`:
1. "twyne-root" provenance comments in pre-edit-guard.sh and hook-utils.sh
2. Hardcoded `/mnt/raid0/` paths in check_filesystem_path.sh
3. `llama-server` + 200GB threshold in inference_guard.sh and run_wrapper.sh
4. `orchestrator llama` example in add-dependency.sh
5. Qwen3-8B / Q4_K_M / inference_endpoint examples in swarm/README.md

Post-fix verification: `grep -ri 'epyc\|twyne\|llama\|Qwen\|Q4_K\|orchestrator\|/mnt/raid0'` returns zero matches.

## Remaining Work (Prioritized)

| Priority | Scope | Items |
|----------|-------|-------|
| ~~P1: Correctness~~ | ~~Issue #2~~ | ~~Fix lock race, normalize scoring, remove dead code, add tests~~ — **DONE** |
| ~~P2: Governance~~ | ~~Issue #1~~ | ~~2 missing validators, numeric literals, recovery scripts, post-init validation~~ — **DONE** |
| ~~P3: Integration~~ | ~~Issues #3-4~~ | ~~Nightshift worker launch, AutoPilot swarm consumer, devcontainer~~ — **DONE** |

## Completed Since Last Update

| Date | Commit | Description |
|------|--------|-------------|
| 2026-03-16 | ea02ec0 | Upstream contribution pipeline |
| 2026-03-16 | 7c8f559 | GitNexus codebase intelligence |
| 2026-03-14 | 4fcb457 | Template gap documentation |
| 2026-03-14 | 4de6809 | Handoff and issue tracker refresh |
| 2026-03-09 | 06e1b31 | Contamination cleanup |

## Next Session

Continue work directly in `/mnt/raid0/llm/root-archetype` — the repo is self-governing with its own `.claude/` config. Use GitHub issues #1-#4 as the backlog.
