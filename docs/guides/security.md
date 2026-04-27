# Security Guide

Out-of-the-box safety measures that every clone of root-archetype inherits, and
how to operate them. The threat model is "an AI agent (Claude Code, Codex, …)
running with broad shell access on a developer workstation" — the goal is to
make accidental and adversarial misbehavior visible, bounded, and reversible.

## Threat Model (in scope)

| Concern | Addressed by |
|---------|-------------|
| Agent reads files it shouldn't (env vars, keys, .ssh/) | Read-side hook (`check_secrets_read.sh`) |
| Agent writes outside the project tree | Write-side hook (`check_filesystem_path.sh`) |
| Agent commits secrets via Edit/Write | Pre-edit secret scan (`pre-edit-guard.sh`) |
| `$PATH` shadowing redirects a hook's `jq` / `git` to a malicious binary | Tool pinning (`tools.lock` + `hook_resolve_tool`) |
| A fork or in-place edit silently disables a gate hook | Hook drift detection (`HOOKS.lock`) |
| Reviewing a session start without running it | Dry-run / argv mode |
| Loss of forensic trail | Append-only audit log |
| Runaway test commands consuming the box | Bounded test safety hook |
| Cross-session state collision between users | Per-user log scoping + session branches |

## Out of scope (deliberately)

- **Acquisition-time integrity**: if you clone a compromised archetype, no
  in-repo measure can save you. Verify the clone source.
- **Kernel sandboxing**: filesystem/network sandboxing at the kernel level
  (firejail, bubblewrap, landlock) is per-deployment and not opinionated here.
  Layer it on top.
- **OS keychain integration**: heterogeneous on Linux. Use `secrets/` (with the
  read-block hook) as the abstract boundary; bind to libsecret/pass/age in
  child repos as needed.

## Defense Layers

### 1. Read-Side Secret Protection (`check_secrets_read.sh`, default-on)

Blocks `Read`, `Glob`, `Grep`, and `Bash` operations that would access protected
paths declared in `secrets/.secretpaths`. The `secrets/` directory itself is
tracked but its contents are gitignored — child repos use it as the canonical
location for files that must never enter agent context.

### 2. Write-Side Filesystem Boundary (`check_filesystem_path.sh`, default-on)

Prevents `Write`/`Edit` to paths outside `$CLAUDE_PROJECT_DIR`. Stops symlink
traversal, accidental absolute-path writes, and the "agent edits its own user
home" failure mode.

### 3. Pre-Edit Secret Scan (`pre-edit-guard.sh`, optional)

Scans content the agent is about to write against the regex patterns in
`scripts/hooks/lib/secret-patterns.txt` (AWS keys, GitHub PATs, OpenAI keys,
private key blocks, …). Blocks the write and emits a redaction suggestion.

Enable in `.claude/settings.json` (or via `init-wizard`).

### 4. Tool Pinning (`tools.lock` + `hook_resolve_tool`)

**Why**: every hook shells out to `jq`, `git`, `python3`, `gh`. If `$PATH`
contains an attacker-controlled directory before the system one, the hook runs
the attacker's binary — bypassing the gate it implements.

**How**: hooks resolve tools via `hook_resolve_tool <name>`, which reads pinned
absolute paths from `scripts/hooks/lib/tools.lock`. The lock is generated
per-installation by:

```bash
scripts/hooks/lib/tools-init.sh           # generate / refresh
scripts/hooks/lib/tools-init.sh --diff    # preview changes
scripts/hooks/lib/tools-init.sh --strict  # fail on missing tools
```

The committed contract is `scripts/hooks/lib/tools.lock.example` — it
declares which tools the hooks depend on. The actual `tools.lock` is gitignored
because absolute paths vary per machine.

**Strict mode**: `ARCHETYPE_HOOK_TOOLS_STRICT=1` turns the fallback-to-`$PATH`
behavior off. Use this in CI and on hardened developer machines.

**Audit**: `hook_tools_audit` prints a per-tool status table:
- `PINNED` — locked path resolves and is executable
- `FALLBACK` — not pinned, resolved via `$PATH`
- `STALE` — pinned path no longer executable
- `MISSING` — neither pinned nor on `$PATH`

### 5. Hook & Validator Drift Detection (`HOOKS.lock`)

**Why**: the gates above are only as trustworthy as the code that runs them. A
hostile fork (or a careless edit) that changes `check_secrets_read.sh` to a
no-op silently disables the gate.

**How**: `HOOKS.lock` (committed) holds sha256 hashes of every file under
`scripts/hooks/` and `scripts/validate/`, except per-installation generated
files (`tools.lock`). Any drift fails `validate_hooks_lock.sh`.

```bash
scripts/validate/validate_hooks_lock.sh           # exit 0 clean, 1 drifted
scripts/validate/validate_hooks_lock.sh --diff    # show drifted files
scripts/validate/update_hooks_lock.sh             # re-approve after review
```

**Operating discipline**: the lock is *meant* to fail loudly until someone
acknowledges the change. Run `update_hooks_lock.sh` only after reading the
diff. Wire `validate_hooks_lock.sh` into CI to catch tampered forks.

### 6. Dry-Run / Argv Mode

Both session entry points print their resolved launch chain without side
effects, supporting security review before trusting a profile:

```bash
bash scripts/hooks/session-start.sh --argv          # human-readable
bash scripts/hooks/session-start.sh --argv json     # JSON
bash scripts/session/session_init.sh --argv
```

Output includes: project dir, log repo dir, planned branch name, planned
writes, declared side effects, and the tool audit table. No files are touched,
no git operations run.

### 7. Append-Only Audit Trail (`post-tool-use-audit.sh`, default-on)

Every Claude Code tool invocation is logged via `scripts/utils/agent_log.sh`
to per-user audit files under `logs/audit/<user>/`. Logs are append-only by
convention; tampering shows up in git diffs of the log repo.

Session counters (`tool_calls`, `subagents`, `file_modifications`) are
maintained in `.session-stats` (gitignored) and surfaced to subagents as
context budget signals.

### 8. Bounded Test Execution (`check_test_safety.sh`, optional)

Caps parallelism and timeouts on agent-issued `Bash` commands that look like
test runners (`pytest`, `cargo test`, `forge test`, …). Prevents the
"agent kicks off a fork-bomb-equivalent test matrix" failure mode.

Enable in `.claude/settings.json` per the patterns in `scripts/hooks/README.md`.

### 9. Schema & Structural Invariants (`scripts/validate/*.py`)

| Validator | Checks |
|-----------|--------|
| `validate_agents_structure.py` | Role files conform to the 6-section schema |
| `validate_agents_references.py` | No dangling references between agents/skills |
| `validate_claude_md_consistency.py` | `CLAUDE.md` / `CODEX.md` / `AGENT.md` agree |
| `validate_document_drift.py` | Templated docs haven't silently diverged |
| `validate_skills.py` | Skills follow YAML frontmatter contract |
| `validate_hooks_lock.sh` | Hook/validator file tree matches `HOOKS.lock` |

Run all of them before merging changes to governance files.

### 10. Session Isolation

`session-start.sh` creates a `session/<short-id>_<date>` branch on every new
session. Per-user identity is persisted to `.session-identity` (gitignored).
Concurrent sessions cannot stomp each other's git state, and forensics can
attribute changes to a specific session id.

### 11. Per-User Log/Notes Scoping

`hook_ensure_log_dirs <user>` creates `notes/<user>/`, `logs/progress/<user>/`,
and (if applicable) `wiki/<user>/` in the log repo. Cross-user collision is
structurally impossible: one agent cannot accidentally overwrite another
user's notes because the path is namespaced by the hook before the agent ever
sees it.

## Setup Checklist (per fresh clone)

```bash
# 1. Pin tools to current installation
scripts/hooks/lib/tools-init.sh

# 2. Generate the hook/validator lock for this checkout
scripts/validate/update_hooks_lock.sh

# 3. Verify everything resolves
bash scripts/hooks/session-start.sh --argv
bash scripts/validate/validate_hooks_lock.sh

# 4. Wire optional hooks if your threat model warrants them
#    (edit guard, schema guard, test safety) — see scripts/hooks/README.md
```

## Operating Discipline (recurring)

| Trigger | Action |
|---------|--------|
| System package upgrade | Re-run `tools-init.sh --diff`, review, accept |
| Hook or validator edit | `update_hooks_lock.sh`, review diff, commit lock |
| Adopting a fork or merging a PR that touches hooks | Run `validate_hooks_lock.sh` before trusting it |
| Adding a new external tool to a hook | Add to `tools.lock.example`, re-run `tools-init.sh`, commit example |
| Suspect compromise | `validate_hooks_lock.sh --diff` + `git log scripts/hooks/ scripts/validate/` |

## Provenance

The pinned-tools / explicit-secret-release / kernel-sandbox / verify-then-trust
model is adapted from the agent-stack hardening pattern described in
[learntoprompt.org / agent-stack](https://learntoprompt.org/guides/agent-stack.html).
Root-archetype implements the portable subset (tool pinning, drift detection,
dry-run verification) and leaves kernel sandboxing and OS keychain integration
as per-deployment concerns.
