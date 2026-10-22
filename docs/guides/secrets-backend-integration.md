# Secrets Backend Integration Guide

How to choose and wire a secrets backend for a root-archetype instance. The rules (tiers, injection, rotation) are in [`secrets-policy.md`](secrets-policy.md); this guide covers the backend options, with Infisical in detail.

## The Rule First

The policy is in [`secrets-policy.md`](secrets-policy.md). In short:

- **Tier-1** credentials (signing keys, write-scope tokens) come from a
  keystore at runtime. They are **never** stored in plaintext, gitignored or not.
- **Tier-2** credentials (read-only scope) should come from a keystore.
  A gitignored plaintext file is acceptable for read-only scope only.
- **Tier-3** values are config and can live anywhere.
- Every Tier-1/2 credential has an entry in `docs/rotation-register.json`.

This guide is about **which backend** holds the values and how to wire it. It
does not change those rules.

## What Ships With Every Instance

| Component | Path | Purpose |
|-----------|------|---------|
| Protected directory | `secrets/` | Gitignored. For encrypted bundles (sops/age) and Tier-2/3 files only |
| Path protection | `secrets/.secretpaths` | Glob patterns blocking agent reads |
| Hook enforcement | `scripts/hooks/check_secrets_read.sh` | Pre-tool-use hook that blocks access to protected paths |
| Commit scanning | `safe-commit` skill, `scripts/githooks/pre-commit` | Pattern-based detection of leaked credentials |
| Reference check | `scripts/utils/check_secret_refs.sh` | Fails a reference file that holds a literal credential or a malformed reference |
| Rotation register | `docs/rotation-register.json` + `scripts/validate/validate_rotation_register.py` | Inventory and rotation clock; fails CI on an overdue rotation or an expired grant |

The read hook stops an **agent** from reading `secrets/`. It does not protect
the file from backups, images, tarballs, or other processes. So `secrets/` is
not a keystore, and it is not a place for Tier-1 values.

## Choosing a Backend

| Situation | Suggested backend |
|-----------|-------------------|
| Small team, people already use a password manager | 1Password CLI (`op run`, `op inject`) |
| Want secrets encrypted in git, no service | sops + age (`sops exec-env`) |
| Solo, Linux, GPG already set up | `pass` |
| Many repos and CI systems, want audit and dynamic credentials | Infisical or HashiCorp Vault |
| Everything already runs in one cloud | That cloud's secrets manager |

Whatever the backend, the wiring is the same pattern
([`secrets-policy.md`](secrets-policy.md) §3): references at rest, resolve at
exec time, the value lives only in the consuming process.

### Example: 1Password CLI

```bash
# Reference file (no values) — check it, then use it
cat > "$HOME/.config/<project>/secret-refs.env" <<'EOF'
DEPLOY_TOKEN=op://<vault>/DEPLOY_TOKEN/credential
EOF
chmod 600 "$HOME/.config/<project>/secret-refs.env"
bash scripts/utils/check_secret_refs.sh "$HOME/.config/<project>/secret-refs.env"

# Run one command with the values resolved
op run --env-file="$HOME/.config/<project>/secret-refs.env" -- <command>
```

### Example: sops + age

```bash
# Encrypted file can be committed; the age private key stays outside the repo
sops --encrypt --age <recipient> secrets.env > secrets.enc.env
sops exec-env secrets.enc.env '<command>'
```

## Option: Infisical (Self-Hosted or Cloud)

[Infisical](https://github.com/Infisical/infisical) is an open-source secrets management platform with a CLI, SDKs, and Kubernetes operator. It uses AES-256-GCM encryption with a hierarchical key model and supports external KMS delegation (AWS KMS, CloudHSM, GCP KMS).

See `knowledge/research/deep-dives/infisical-secrets-management-platform.md` for a detailed technical breakdown.

### Setup (Self-Hosted)

1. **Deploy Infisical** alongside your root-archetype host:

```bash
# Clone and start (requires Docker)
git clone https://github.com/Infisical/infisical.git /opt/infisical
cd /opt/infisical
docker compose -f docker-compose.prod.yml up -d
```

2. **Install the CLI**:

```bash
# macOS
brew install infisical/get-cli/infisical

# Linux (Debian/Ubuntu)
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo bash
sudo apt-get install infisical
```

3. **Create a project** in the Infisical dashboard for your root-archetype instance.

4. **Authenticate**:

```bash
# Interactive login (for local dev)
infisical login

# Machine identity (for CI/scripts)
export INFISICAL_TOKEN=$(infisical login --method=universal-auth \
  --client-id=YOUR_CLIENT_ID \
  --client-secret=YOUR_CLIENT_SECRET \
  --plain)
```

### Wiring Into Root-Archetype

The integration point is `secrets/` — replace static files with Infisical CLI calls.

**Option A: Wrapper script** — Tier-2/3 only

> **Warning:** This loads every value into the session environment, and every
> child process inherits it — an agent session included. Do not use it for
> Tier-1 credentials. Use Option B for those.

Create `scripts/utils/load_secrets.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Loads secrets from Infisical into environment for the current session.
# Falls back to secrets/.env if Infisical is unavailable.

if command -v infisical &>/dev/null && infisical export --silent >/dev/null 2>&1; then
    eval "$(infisical export --format=dotenv-export)"
    echo "[secrets] Loaded from Infisical"
else
    if [[ -f secrets/.env ]]; then
        set -a
        source secrets/.env
        set +a
        echo "[secrets] Loaded from secrets/.env (Infisical unavailable)"
    else
        echo "[secrets] WARNING: No secrets source available" >&2
    fi
fi
```

**Option B: Run commands with injected env** (recommended; no script changes needed)

```bash
# Any command gets secrets injected automatically
infisical run -- bash scripts/session/session_init.sh
infisical run -- your-audit-command
```

### What Stays the Same

Regardless of backend, these remain unchanged:

- **`.secretpaths`** — still blocks agent reads (agents never touch Infisical directly)
- **`check_secrets_read.sh`** — still enforces path protection
- **`safe-commit`** — still scans for leaked patterns in staged diffs
- **`secrets/` directory** — still exists for encrypted bundles and Tier-2/3 values
- **`docs/rotation-register.json`** — still the inventory; `store` points at the Infisical path

### Init-Wizard Integration (Future)

When the init-wizard runs, a secrets backend step could offer:

```
Step N: Configure secrets backend
  [1] .env files in secrets/ (default — no dependencies)
  [2] Infisical (requires running instance or cloud account)
  [3] Custom (bring your own — write scripts/utils/load_secrets.sh)
```

This is not yet implemented. To add it, extend `agents/skills/init-wizard/SKILL.md` with a step that:
1. Asks the user for their choice
2. For Infisical: validates `infisical` CLI is installed, runs `infisical init`
3. Writes `scripts/utils/load_secrets.sh` with the appropriate backend
4. Updates `scripts/session/session_init.sh` to source it

## Other Options

The wrapper pattern above works with any secrets backend that can export to env vars:

| Backend | CLI Export Command | Notes |
|---------|--------------------|-------|
| Infisical | `infisical export --format=dotenv-export` | Open source, self-hostable |
| HashiCorp Vault | `vault kv get -format=json ... \| jq ...` | Industry standard, heavier ops burden |
| Doppler | `doppler secrets download --no-file --format=env-no-quotes` | Cloud-only, simple UX |
| 1Password CLI | `op inject < template.env` | Good for small teams already using 1P |
| AWS Secrets Manager | `aws secretsmanager get-secret-value ...` | Native if already on AWS |

The hook-based protection layer is backend-agnostic — it protects against agent access regardless of where secrets are stored.
