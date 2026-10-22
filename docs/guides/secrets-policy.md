# Secrets Policy — Storage, Injection, Rotation

The default credential model for every project spawned from this archetype.
It says **what must be true**, not which product to buy. Backend choice
(1Password, Infisical, sops+age, pass, Vault, a cloud secrets manager) is per
project; the rules below apply to all of them.

Related:
- [`security.md`](security.md) — the hook layers that enforce part of this
- [`secrets-backend-integration.md`](secrets-backend-integration.md) — backend options and wiring
- [`../rotation-register.json`](../rotation-register.json) — the inventory and rotation clock

> **Warning:** Never paste a private key, seed phrase, keystore password or
> live token into an agent session (Claude Code, Codex, or any other). The
> transcript, the audit log and any subagent keep a copy. The secret scanners
> match known shapes only; they do not catch every credential.

## 1. Tiers

Classify every credential before you decide where it lives.

| Tier | A leak causes | Examples | Storage rule |
|------|---------------|----------|--------------|
| **1** | Loss of funds, irreversible writes, or compromise of another system | Signing keys, deployer keys, write-scope cloud keys, write API tokens, bot tokens that can post or read DMs | **Keystore at runtime. Never on disk in plaintext, gitignored or not.** |
| **2** | Quota burn, reconnaissance, or exposure of read-only data; reversible by rotation | Read-only cloud keys, RPC/provider URLs with an embedded key, read-scope API keys | Keystore preferred. A gitignored plaintext file is acceptable only for read-only scope. |
| **3** | Nothing — it is config | Ports, log levels, public endpoints, public addresses, feature flags | Plaintext is fine. Not tracked in the register. |

If you are not sure between two tiers, use the higher tier.

Why gitignored is not enough for Tier-1: a gitignored `.env` still leaks
through container images, backups and tarballs, search indexes, terminal
scrollback, and any agent or subagent that reads it.

## 2. Rules for agents (hard)

1. **Never handle a value.** Do not read, echo, quote, log or summarize a
   credential value — not even one the operator just pasted. Acknowledge it
   without the value, and tell the operator to rotate it (§6.2).
2. **Never re-export.** Do not read a secret in one process and `export` it
   into a shell, a child process or a subagent. The keystore wrapper runs the
   consuming command directly (§3.1).
3. **Never propose plaintext for Tier-1** — not `.env`, not `secrets/`, not a
   shell profile. If the tier is not clear, ask.
4. **Templates use references.** Generated `.env.example` / template entries
   for a Tier-1 or Tier-2 credential use the keystore reference form, with the
   plaintext fallback (Tier-2 only) marked "NOT RECOMMENDED".
5. **Register what you create.** A new credential or a temporary grant that an
   agent sets up (or asks the operator to set up) gets a register entry in the
   same change (§5). A temporary grant with no expiry is not allowed.
6. **Nudge.** When an operator asks "where do I put this key?", wants to add a
   secret to `.env`, or runs `export SECRET=...`, answer with this policy, not
   with the literal request.

## 3. Injection model

The keystore is the only place a value lives at rest. Everything else holds
**references**, and each consumer resolves them at the moment it runs.

```
keystore item  ──reference──▶  reference file  ──resolve at exec──▶  consumer process env
 (value at rest)               (tracked or host)   (wrapper / inject)    (value in memory only)
```

### 3.1 Local commands

Wrap the consuming command so the value exists only in that process:

```bash
# 1Password: reference file holds op:// references, op resolves at exec time
op run --env-file="$HOME/.config/<project>/secret-refs.env" -- <command>

# sops + age: encrypted file in the repo, decrypted into the child env only
sops exec-env secrets.enc.env '<command>'
```

Do **not** use `export VAR=$(keystore read ...)` in an interactive shell, and
do not source a resolved file into a session that starts an agent.

### 3.2 The reference file

- One file per scope (for example "agent session", "deploy", "bot"). A
  process gets only the variables its task needs.
- It holds references only, so it is safe to read and to track as a
  template. Keep the host copy `chmod 600` anyway; it names your items.
- Check it with `scripts/utils/check_secret_refs.sh <file>`. The check fails
  on a literal credential and on a malformed `op://` reference.
- 1Password item titles must be path-safe: `op://` references reject spaces
  and brackets. `op inject` also resolves references inside `#` comments, so a
  malformed reference in a comment still breaks the run.

### 3.3 Devcontainers

Resolve on the **host**, then forward resolved values into the container
session. Do not mount the keystore session (`~/.config/op`, `~/.gnupg`, cloud
CLI configs) into the container: any process in it, including an agent, could
then read every item.

```jsonc
// .devcontainer/devcontainer.json
"remoteEnv": {
  "SOME_API_KEY": "${localEnv:SOME_API_KEY}"
}
```

`${localEnv:...}` is resolved from the shell that runs `devcontainer up` /
`exec`, **on every exec**. So every launcher that opens a shell in the
container must itself run under the wrapper; a launcher that does not forwards
empty strings. Do not put Tier-1/2 values in `docker-compose.yml`
`environment:` or in `.devcontainer/.env`.

### 3.4 CI and servers

- The CI secret store holds **one** credential: a keystore machine identity
  (service account, Connect token) that is **read-only** and scoped to the
  one vault or project the job needs. Where the platform supports OIDC
  federation, use that and store nothing.
- The deploy step: check the template (`check_secret_refs.sh`), inject, then
  check the output (`check_secret_refs.sh --resolved`) so a missing item fails
  the deploy and does not ship an empty variable. Never print the resolved file.
- A resolved file on a server (`op inject` output, a rendered k8s Secret, a CI
  environment secret) is a **copy**. List every copy in the register (§5). A
  copy does not update itself when the keystore item changes.

## 4. Credential choice

Prefer credentials that expire on their own:

| Instead of | Prefer |
|------------|--------|
| Static cloud access-key pair for a person or agent | SSO / role sessions with short lifetimes |
| Classic personal access token with no expiry | Fine-grained token with an expiry, or an app installation token |
| Long-lived CI deploy key | OIDC federation from CI to the cloud or registry |
| One shared key for many consumers | One key per consumer, so you can revoke one without the others |

A credential with no upstream expiry is still on the rotation clock (§6.1).

## 5. The register

`docs/rotation-register.json` is the inventory. It holds metadata and
references, **never a value**. `scripts/validate/validate_rotation_register.py`
checks it; CI runs every validator.

```json
{
  "id": "DEPLOY_TOKEN",
  "tier": 1,
  "owner": "<github-handle>",
  "store": "op://<vault>/DEPLOY_TOKEN/credential",
  "consumers": ["ci: deploy workflow"],
  "copies": ["CI environment secret 'production'"],
  "rotation_days": 90,
  "last_rotated": "2026-10-01",
  "expires": "2027-10-01",
  "procedure": "docs/runbooks/deploy-token.md"
}
```

| Field | Meaning |
|-------|---------|
| `id` | Env var name or logical name. Unique. |
| `tier` | 1, 2 or 3 (§1). Tier-3 entries have no clock. |
| `owner` | The person who rotates it and answers for it. |
| `store` | Keystore locator `<backend>:<locator>`. A URL or a raw value fails. |
| `consumers` | What reads it. |
| `copies` | Every place a **resolved** value is stored. `[]` if consumers resolve at runtime. |
| `rotation_days` | Rotation interval. Must not exceed the tier maximum in `policy`. |
| `last_rotated` | `YYYY-MM-DD`. |
| `expires` | Optional. Upstream hard expiry. |
| `procedure` | Where the rotation steps for this credential are written. |

Temporary grants (a time-boxed role, policy, token or allow-list entry) go in
`temporary_grants` with `id`, `owner`, `scope`, `granted`, `expires`, and
optionally `ticket`. A grant longer than `policy.max_grant_days` fails.

The validator **fails** on: an overdue rotation, a passed `expires`, an expired
grant, a missing field, a tier maximum exceeded, a store that is not a
locator, and any string that matches a secret pattern. It **warns** when a
date is within `policy.due_soon_days`. So an overdue key turns CI red — that
is intended. Fix it by rotating, not by moving the date.

## 6. Rotation

### 6.1 Cadence

| Tier | Maximum interval (default `policy`) |
|------|--------------------------------------|
| 1 | 90 days |
| 2 | 180 days |
| 3 | none |
| Temporary grant | expires at most 30 days after it is granted |

A project can make these shorter in the register's `policy` block. Making them
longer is a reviewed change to that block, with the reason in the PR.

### 6.2 Event triggers — rotate now, do not wait for the clock

- You suspect a leak, or a value was committed or pushed.
- A value went through an agent session, a shell history, a clipboard, a
  chat, or a screen share.
- A person who had access leaves or changes role.
- A provider sends a breach or deprecation notice.
- You move the value from one store to another (for example `.env` →
  keystore). It passed through your editor and shell on the way.

### 6.3 Procedure

Do the steps in this order. Write credential-specific details in the entry's
`procedure` file.

1. **Make the new value** in the upstream system. Keep the old one valid
   (overlap) if the system allows two.
2. **Write the new value to the keystore item.** Keep the item and the
   reference the same, so reference files do not change.
3. **Re-render every copy** listed in `copies`.
4. **Restart or redeploy every consumer.** Verify each one with a check that
   does not print the value (an authenticated call that returns OK).
5. **Revoke the old value** upstream. Verify that the old value now fails.
6. **Update the register**: `last_rotated`, `expires`, and `copies` if they
   changed. Commit.

For a leak, revoke as soon as step 4 is done for the critical consumers; if
the value is already public, revoke first and accept the downtime. Rewrite git
history only **after** revocation: the exposure window ends when the value
stops working, not when the commit disappears.

### 6.4 Temporary grants

- Set the expiry when you make the grant. Prefer a mechanism that expires on
  its own (session duration, token expiry, a policy condition on time).
- Add the entry to `temporary_grants` in the same change.
- When the grant expires, the validator fails until someone revokes the grant
  upstream and removes the entry, or renews it with a new expiry.

## 7. Adoption checklist (per project)

1. Pick a backend ([`secrets-backend-integration.md`](secrets-backend-integration.md)).
2. Classify every existing credential by tier.
3. Move Tier-1 (and, where possible, Tier-2) values into the keystore. Delete
   them from every `.env`. Rotate them (§6.2: they moved through your shell).
4. Write the reference files and check them with `check_secret_refs.sh`.
5. Add a register entry for every Tier-1/2 credential and every live grant.
6. Run `python3 scripts/validate/validate_rotation_register.py`.
