# Secrets Backend Integration Guide

How to manage secrets in a root-archetype instance. Covers the default `.env` approach and optional upgrade paths including Infisical.

## Default: `.env` + Hook Protection

Every root-archetype instance ships with file-based secrets management:

| Component | Path | Purpose |
|-----------|------|---------|
| Secret store | `secrets/` | Gitignored directory for credential files |
| Path protection | `secrets/.secretpaths` | Glob patterns blocking agent reads |
| Hook enforcement | `scripts/hooks/check_secrets_read.sh` | Pre-tool-use hook that blocks access to protected paths |
| Commit scanning | `safe-commit` skill | Pattern-based detection of leaked credentials |

**This is sufficient when**: you're a solo operator, secrets are few (<20 values), rotation is manual and infrequent, and there's no team sharing credentials.

### Usage

```bash
# Store secrets
echo "ANTHROPIC_API_KEY=sk-ant-..." > secrets/.env

# Reference from scripts
source secrets/.env

# Agent access is blocked automatically by the hook
```

## When to Upgrade

Consider a dedicated secrets backend when any of these apply:

- **Team access**: Multiple people or CI systems need the same credentials
- **Rotation pressure**: API keys expire or must rotate on a schedule
- **Audit requirements**: You need a log of who accessed which secret and when
- **Dynamic credentials**: You want short-lived database credentials generated on demand
- **Multi-repo**: Several child repos registered under this root share credentials

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

**Option A: Wrapper script** (recommended for simplicity)

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

**Option B: Run commands with injected env** (no script changes needed)

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
- **`secrets/` directory** — still exists as fallback and for any values not in Infisical

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
