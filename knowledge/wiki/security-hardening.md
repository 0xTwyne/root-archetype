# Security & Hardening

**Category**: governance

Tool pinning, hook drift detection, dry-run verification, and the project's threat model.

## Summary

Root-archetype ships a portable hardening baseline so any clone has working agent-safety primitives before customization. The threat model centers on "an AI agent running with broad shell access on a developer workstation" — measures aim to make accidental and adversarial misbehavior visible, bounded, and reversible.

Tool pinning closes the `$PATH`-shadowing gap: hooks resolve `jq` / `git` / `python3` via pinned absolute paths in `scripts/hooks/lib/tools.lock` (per-installation, gitignored) checked against `tools.lock.example` (committed contract). `hook_resolve_tool` in `lib/hook-utils.sh` is the canonical accessor; fail-soft by default with `ARCHETYPE_HOOK_TOOLS_STRICT=1` opt-in.

Drift detection uses `HOOKS.lock` (committed) — sha256 over every file under `scripts/hooks/` and `scripts/validate/`, excluding the per-installation `tools.lock`. `validate_hooks_lock.sh` exits non-zero on drift; `update_hooks_lock.sh` is the explicit re-approval step. Silent fork tampering and in-place edits to gate code can no longer pass unnoticed.

Dry-run / argv mode on `session-start.sh` and `session_init.sh` (`--argv` / `--dry-run`) prints the resolved launch chain — paths, planned writes, side effects, tool audit — without executing. Out of scope deliberately: kernel sandboxing (per-deployment) and OS-keychain integration (heterogeneous on Linux); both are documented as omissions in `docs/guides/security.md`.

## Key Points

- Tool pinning: `tools.lock` (gitignored) + `tools.lock.example` (committed contract); `hook_resolve_tool` is the helper
- `tools-init.sh` generator: `--diff` previews, `--strict` fails on missing tools
- `ARCHETYPE_HOOK_TOOLS_STRICT=1` disables fail-soft fallback to `command -v`
- `HOOKS.lock` = sha256 over `scripts/hooks/` + `scripts/validate/`; `tools.lock` excluded
- `validate_hooks_lock.sh --diff` shows drift; `update_hooks_lock.sh` is the acknowledged re-approval
- Dry-run modes: `session-start.sh --argv [json]` and `session_init.sh --argv` — zero side effects
- Kernel sandboxing and OS-keychain integration deliberately out of scope; documented in `docs/guides/security.md`
- Governance hygiene: `lint_wiki.py` 5-pass linter (orphan, stale, contradiction, un-actioned, missing cross-ref)

## See Also

- [`docs/guides/security.md`](../../docs/guides/security.md) — full reference: threat model, 11 defense layers, setup checklist
- [`scripts/hooks/lib/tools.lock.example`](../../scripts/hooks/lib/tools.lock.example) — committed tool contract
- [`scripts/hooks/lib/tools-init.sh`](../../scripts/hooks/lib/tools-init.sh) — generator for the per-installation lock
- [`scripts/validate/validate_hooks_lock.sh`](../../scripts/validate/validate_hooks_lock.sh) — drift detector
- [Hook System & Governance](hook-system-governance.md) — the underlying hook architecture
- [learntoprompt.org / agent-stack](https://learntoprompt.org/guides/agent-stack.html) — source of the portable hardening pattern adopted here
