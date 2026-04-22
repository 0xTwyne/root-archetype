# Knowledge Base Linter & Governance Hygiene Patterns

**Status**: completed
**Created**: 2026-04-06 (via research intake deep-dive)
**Categories**: governance, validation, upstream
**Origin**: intake-268 (Karpathy LLM Wiki), intake-269 (nvk/llm-wiki), intake-270 (tobi/qmd)

## Objective

Upstream knowledge-base hygiene patterns into root-archetype so all instances inherit them. Governance repos are LLM-compiled knowledge bases (Karpathy, intake-268) — they need the same lint operations a wiki does: orphan detection, staleness flagging, contradiction detection, and follow-through validation.

Root-archetype has 5 validators but none that lint the knowledge base itself. This handoff closes that gap and adds skill-template patterns for credibility scoring, anti-confirmation-bias, and session persistence.

---

## Outstanding Tasks (Priority Order)

### Phase 1 — Upstream freshness check (P0)

- [x] Port `check_handoff_freshness.sh` from epyc-root — ✅ 2026-04-07. SUPERSEDED: freshness checking absorbed into project-wiki skill lint operation (stale_entries pass). The standalone shell script is still available in epyc-root with portable paths (no more hardcoded `/mnt/raid0/`).
- [x] Add `knowledge-lint` task to `nightshift.yaml` — ✅ 2026-04-07. Done in epyc-root. Root-archetype nightshift.yaml updated as part of project-wiki skill.

### Phase 2 — Knowledge base linter (P0)

- [x] Create lint implementation — ✅ 2026-04-07. SUPERSEDED by project-wiki skill: `.claude/skills/project-wiki/scripts/lint_wiki.py` with 5 passes (orphan, stale, contradictory, un-actioned, missing cross-refs). Config-driven via `wiki.yaml`. Validated in epyc-root first (found 4 errors + 71 warnings), then upstreamed.
- [x] Register linter — ✅ 2026-04-07. Part of project-wiki skill, wired to nightshift in epyc-root.
- [x] Add to `CLAUDE.md` validators list — ✅ 2026-04-09 Added project-wiki skill to Skills section

### Phase 3 — Skill template additions (P1)

- [x] Create `_templates/skill/references/credibility-scoring-rubric.md` — ✅ 2026-04-07. 6-point rubric with High/Medium/Low tiers and skip criteria.
- [x] Add commented anti-confirmation-bias section to `_templates/skill/SKILL.md.template` — ✅ 2026-04-09

### Phase 4 — Session persistence template (P2)

- [x] Create `_templates/skill/references/session-persistence-schema.md` — ✅ 2026-04-09

---

## Dependency Graph

```
Phase 1 (freshness check)    ── independent, quick port ──
Phase 2 (linter)             ── independent, main deliverable ──
Phase 3 (skill templates)    ── independent, template additions ──
Phase 4 (session persistence) ── independent, documentation only ──
```

No inter-phase dependencies. All phases can be executed in any order.

---

## Cross-Cutting Concerns

1. **Linter ↔ validate_document_drift.py**: The existing drift validator checks structural requirements (required dirs/files exist, handoff status vs directory). The new linter checks *knowledge quality* (orphans, staleness, contradictions). These are complementary — lint_knowledge_base.py should import nothing from validate_document_drift.py to keep them decoupled.

2. **Freshness check ↔ nightshift**: The freshness check produces a human-readable report. When run as a nightshift task, output should be captured in `logs/nightshift/` and surfaced in the umbrella PR's "needs_review" section.

3. **Intake detection ↔ research skill**: The un-actioned intake lint pass only works if the instance has a `research/intake_index.yaml`. The linter should gracefully skip this pass if the file doesn't exist (not all instances will have research intake).

4. **Upstream from epyc-root**: The freshness check script originates from epyc-root. Once upstreamed, epyc-root should replace its local copy with a symlink or note pointing to the archetype version to avoid drift.

---

## Reporting Instructions

After completing any phase:
1. Check the task checkbox in this handoff
2. Run all existing validators to confirm no regressions: `for f in scripts/validate/*.py; do python3 "$f"; done`
3. Update `progress/YYYY-MM/YYYY-MM-DD.md` in root-archetype

---

## Key File Locations

| Resource | Path |
|----------|------|
| Existing validators | `scripts/validate/validate_*.py` |
| Source freshness check (epyc-root) | `/mnt/raid0/llm/epyc-root/scripts/validate/check_handoff_freshness.sh` |
| Nightshift config | `nightshift.yaml` |
| Skill template | `_templates/skill/SKILL.md.template` |
| Template references dir | `_templates/skill/references/` |
| CLAUDE.md (validators list) | `CLAUDE.md` line 29-34 |

## Research Context

| Intake ID | Title | Relevance | Verdict |
|-----------|-------|-----------|---------|
| intake-268 | LLM Wiki (Karpathy) | high | adopt_patterns |
| intake-269 | nvk/llm-wiki | high | adopt_patterns |
| intake-270 | tobi/qmd | high | adopt_component |

**Key insight**: Governance repos are LLM-compiled knowledge bases. The same hygiene operations that keep a wiki healthy (lint for contradictions, orphans, staleness, gaps) apply directly to handoff-based governance. This handoff operationalizes that insight for root-archetype.
