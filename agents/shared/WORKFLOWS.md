# Standard Workflows

## New Feature

1. Add/extend feature flag
2. Implement guarded behavior
3. Add tests for enabled and disabled states
4. Document architecture impact

## Bug Fix

1. Reproduce with minimal test case
2. Identify root cause
3. Fix with targeted change
4. Verify fix and add regression test

## System Change

1. Capture current system state
2. Log rollback command
3. Apply change via audited commands
4. Validate expected impact and stability

## Harness Change Evaluation

1. Measure baseline metrics (success rate, cost, instruction overhead)
2. Apply harness change (prompt edit, tool addition, hook)
3. Run same eval suite on changed harness
4. Compare: quality delta, cost delta, instruction_token_ratio delta
5. Accept only if quality holds AND cost increase is proportionate
6. If adding instructions: verify they're essential-toolchain, not nice-to-have

## Handoff Closure

1. Reconcile handoff checklist against real code/tests
2. Extract durable findings into docs
3. Update roadmap/blocker trackers
4. Record evidence in progress logs
5. Move handoff from `active/` to `completed/`
