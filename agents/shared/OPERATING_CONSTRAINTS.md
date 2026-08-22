# Operating Constraints

Shared constraints for all agent roles in this project.

## Filesystem and Storage

- All artifacts must be written under the project root or approved paths
- Environment variables for caches (HF_HOME, PIP_CACHE_DIR, TMPDIR) should be configured in session_init.sh
- Never write to system directories without explicit approval

### Where working files go

- **`tmp/`** — scratch that another session or collaborator may need to read:
  experiment output, intermediate data, a scratch clone of a child repo.
  Contents are gitignored; the directory is tracked so it exists on every clone.
- **`local/notes/`** — personal material that should persist across sessions.
- **The engine's own session scratchpad** — only for files nobody else will ever
  need. It is per-session and disappears; it is not a substitute for `tmp/`.

Never put working files in a directory outside the root clone, including a
sibling clone of a child repo. Nothing there is readable by other sessions, and
the wrap-up survey walks only `.` and `repos/*/`, so it cannot report the work as
unpushed. Enforced for `Write`/`Edit` by `scripts/hooks/check_filesystem_path.sh`;
**script output written via `Bash` is not covered**, so a script's `--output` path
is the agent's responsibility.

If a child repo needs a scratch clone, put it at `tmp/<repo>-<purpose>/`. Work
that should outlive the session belongs on a branch of the repo it came from,
pushed the same session.

## Test Safety

- Never run tests with unbounded parallelism (e.g., `pytest -n auto` on high-core machines)
- Maximum test worker count: 16 (configurable per project)
- Enforced by hook: `scripts/hooks/check_test_safety.sh`

## Logging and Traceability

- Source `scripts/utils/agent_log.sh` for all operational tasks
- Record task start/end, decisions, rollback commands
- Append-only audit log in `logs/agent_audit.log`

## Retry Policy

- Maximum 3 retries for failing commands
- After 3 failures: root-cause analysis required
- Do not retry in a tight loop — diagnose first

## Dangerous Operations

Require explicit confirmation + rollback planning:
- Recursive deletes in data/model directories
- System-level privileged changes
- Force-push or destructive git operations
