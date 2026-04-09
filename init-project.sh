#!/bin/bash
set -euo pipefail

# Root-Archetype Project Initializer
# Usage: ./init-project.sh <project-name> <project-root> [--repos "name:path,name:path"]

usage() {
    echo "Usage: $0 <project-name> <project-root> [--repos \"name:path,name:path\"] [--email \"user@example.com\"]"
    echo ""
    echo "  project-name   Short identifier (e.g., my-project)"
    echo "  project-root   Absolute path where the root repo will be created"
    echo "  --repos        Comma-separated child repos to register (name:path pairs)"
    echo "  --email        Maintainer email for the seeded project"
    echo ""
    echo "Example:"
    echo "  $0 my-project /tmp/test --repos \"app:/tmp/app,lib:/tmp/lib\" --email \"dev@example.com\""
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

PROJECT_NAME="$1"
PROJECT_ROOT="$2"
shift 2

REPOS=""
MAINTAINER_EMAIL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repos)
            REPOS="$2"
            shift 2
            ;;
        --email)
            MAINTAINER_EMAIL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

ARCHETYPE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Root-Archetype Project Initializer ==="
echo "Project:  ${PROJECT_NAME}"
echo "Root:     ${PROJECT_ROOT}"
echo "Email:    ${MAINTAINER_EMAIL:-not set}"
echo "Repos:    ${REPOS:-none}"
echo ""

# --- Create project directory ---
if [[ -d "${PROJECT_ROOT}" ]]; then
    echo "WARNING: ${PROJECT_ROOT} already exists. Merging into existing directory."
else
    mkdir -p "${PROJECT_ROOT}"
fi

# --- Initialize git if needed ---
if [[ ! -d "${PROJECT_ROOT}/.git" ]]; then
    git init "${PROJECT_ROOT}"
    cd "${PROJECT_ROOT}"
    git checkout -b main 2>/dev/null || true
else
    cd "${PROJECT_ROOT}"
fi

# --- Archetype development directories (NOT copied to clones) ---
# progress/    — archetype's own development log
# handoffs/    — archetype's own work tracking
# logs/        — archetype's own session logs
# These directories are created empty in clones (see mkdir below).

# --- Copy archetype structure ---
echo "Copying archetype structure..."

# Directories
mkdir -p agents/shared
mkdir -p scripts/{hooks,validate,session,nightshift,utils,repos,upstream}
mkdir -p .claude/{commands,skills/swarm,skills/upstream}
mkdir -p handoffs/{active,blocked,completed,archived}
mkdir -p progress
mkdir -p docs/guides
mkdir -p .devcontainer
mkdir -p logs
mkdir -p coordination
mkdir -p swarm
mkdir -p secrets

# --- Template substitution function ---
substitute() {
    local file="$1"
    sed -i \
        -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
        -e "s|{{PROJECT_ROOT}}|${PROJECT_ROOT}|g" \
        -e "s|{{MAINTAINER_EMAIL}}|${MAINTAINER_EMAIL}|g" \
        "$file"
}

# --- Copy and substitute template files ---
copy_and_sub() {
    local src="$1"
    local dst="$2"
    if [[ -f "${ARCHETYPE_DIR}/${src}" ]]; then
        cp "${ARCHETYPE_DIR}/${src}" "${dst}"
        substitute "${dst}"
    fi
}

# Core governance files
copy_and_sub "CLAUDE.md" "CLAUDE.md"
copy_and_sub "README.md" "README.md"
copy_and_sub "SPEC.md" "SPEC.md"

# Agent system
for f in "${ARCHETYPE_DIR}"/agents/*.md; do
    [[ -f "$f" ]] && cp "$f" "agents/$(basename "$f")"
done
for f in "${ARCHETYPE_DIR}"/agents/shared/*.md; do
    [[ -f "$f" ]] && cp "$f" "agents/shared/$(basename "$f")"
done

# Hooks (all copied, user enables via settings.json)
for f in "${ARCHETYPE_DIR}"/scripts/hooks/*.sh; do
    [[ -f "$f" ]] && cp "$f" "scripts/hooks/$(basename "$f")" && chmod +x "scripts/hooks/$(basename "$f")"
done

# Validators
for f in "${ARCHETYPE_DIR}"/scripts/validate/*; do
    [[ -f "$f" ]] && cp "$f" "scripts/validate/$(basename "$f")"
done
chmod +x scripts/validate/*.py 2>/dev/null || true

# Session management
for f in "${ARCHETYPE_DIR}"/scripts/session/*.sh; do
    [[ -f "$f" ]] && cp "$f" "scripts/session/$(basename "$f")" && chmod +x "scripts/session/$(basename "$f")"
done

# Nightshift
for f in "${ARCHETYPE_DIR}"/scripts/nightshift/*.sh; do
    [[ -f "$f" ]] && cp "$f" "scripts/nightshift/$(basename "$f")" && chmod +x "scripts/nightshift/$(basename "$f")"
done
copy_and_sub "nightshift.yaml" "nightshift.yaml" 2>/dev/null || true

# Utils
for f in "${ARCHETYPE_DIR}"/scripts/utils/*.sh; do
    [[ -f "$f" ]] && cp "$f" "scripts/utils/$(basename "$f")" && chmod +x "scripts/utils/$(basename "$f")"
done

# Repo management
for f in "${ARCHETYPE_DIR}"/scripts/repos/*.sh; do
    [[ -f "$f" ]] && cp "$f" "scripts/repos/$(basename "$f")" && chmod +x "scripts/repos/$(basename "$f")"
done

# Swarm coordination
for f in "${ARCHETYPE_DIR}"/swarm/*.py "${ARCHETYPE_DIR}"/swarm/*.md; do
    [[ -f "$f" ]] && cp "$f" "swarm/$(basename "$f")"
done

# Claude Code config
copy_and_sub ".claude/settings.json" ".claude/settings.json" 2>/dev/null || true
for f in "${ARCHETYPE_DIR}"/.claude/commands/*.md; do
    [[ -f "$f" ]] && cp "$f" ".claude/commands/$(basename "$f")"
done
for f in "${ARCHETYPE_DIR}"/.claude/skills/swarm/*; do
    [[ -f "$f" ]] && cp "$f" ".claude/skills/swarm/$(basename "$f")"
done
for f in "${ARCHETYPE_DIR}"/.claude/skills/upstream/*; do
    [[ -f "$f" ]] && cp "$f" ".claude/skills/upstream/$(basename "$f")"
done

# Project-wiki skill (KB governance: lint + query)
if [[ -d "${ARCHETYPE_DIR}/.claude/skills/project-wiki" ]]; then
    mkdir -p .claude/skills/project-wiki/{scripts,references}
    for f in "${ARCHETYPE_DIR}"/.claude/skills/project-wiki/*; do
        [[ -f "$f" ]] && cp "$f" ".claude/skills/project-wiki/$(basename "$f")"
    done
    for f in "${ARCHETYPE_DIR}"/.claude/skills/project-wiki/scripts/*; do
        [[ -f "$f" ]] && cp "$f" ".claude/skills/project-wiki/scripts/$(basename "$f")"
    done
    for f in "${ARCHETYPE_DIR}"/.claude/skills/project-wiki/references/*; do
        [[ -f "$f" ]] && cp "$f" ".claude/skills/project-wiki/references/$(basename "$f")"
    done
fi


# Hook library and policy hooks
mkdir -p .claude/hooks/lib
for f in "${ARCHETYPE_DIR}"/.claude/hooks/*.sh; do
    [[ -f "$f" ]] && cp "$f" ".claude/hooks/$(basename "$f")" && chmod +x ".claude/hooks/$(basename "$f")"
done
for f in "${ARCHETYPE_DIR}"/.claude/hooks/lib/*; do
    [[ -f "$f" ]] && cp "$f" ".claude/hooks/lib/$(basename "$f")"
done

# Wiki structure (wiki.yaml + SCHEMA.md scaffold)
if [[ -f "${ARCHETYPE_DIR}/_templates/wiki.yaml.template" ]]; then
    mkdir -p wiki
    cp "${ARCHETYPE_DIR}/_templates/wiki.yaml.template" "wiki.yaml"
    substitute "wiki.yaml"
    # Create minimal SCHEMA.md
    cat > "wiki/SCHEMA.md" <<'WIKIEOF'
# Wiki Schema — Living Taxonomy

> Authoritative taxonomy for this project. Add categories and aliases as needed.
> Updated: $(date +%Y-%m-%d)

## Categories

| Key | Label | Description |
|-----|-------|-------------|
| `general` | General | Default category for uncategorized entries |

## Aliases

| Alias | Maps To |
|-------|---------|
WIKIEOF
fi

# Secrets protection
cp "${ARCHETYPE_DIR}/secrets/.secretpaths" "secrets/.secretpaths"
touch "secrets/.gitkeep"

# Sandbox settings template (user customizes)
if [[ -f "${ARCHETYPE_DIR}/_templates/settings.local.json.template" ]]; then
    cp "${ARCHETYPE_DIR}/_templates/settings.local.json.template" ".claude/settings.local.json"
fi

# Devcontainer
copy_and_sub ".devcontainer/devcontainer.json" ".devcontainer/devcontainer.json" 2>/dev/null || true

# Maintainers config (required by tamper-proofing hook)
if [[ -f "${ARCHETYPE_DIR}/.claude/maintainers.json" ]]; then
    cp "${ARCHETYPE_DIR}/.claude/maintainers.json" ".claude/maintainers.json"
    substitute ".claude/maintainers.json"
fi

# Upstream contribution scripts
for f in "${ARCHETYPE_DIR}"/scripts/upstream/*.sh; do
    [[ -f "$f" ]] && cp "$f" "scripts/upstream/$(basename "$f")" && chmod +x "scripts/upstream/$(basename "$f")"
done

# --- Build repo map rows for CLAUDE.md ---
REPO_MAP_ROWS=""
if [[ -n "$REPOS" ]]; then
    echo "Registering child repos..."
    IFS=',' read -ra REPO_PAIRS <<< "$REPOS"
    for pair in "${REPO_PAIRS[@]}"; do
        IFS=':' read -r name path <<< "$pair"
        name=$(echo "$name" | xargs)
        path=$(echo "$path" | xargs)
        REPO_MAP_ROWS="${REPO_MAP_ROWS}| ${name} | \`${path}\` | (configure purpose) |\n"
    done
    # Substitute repo map into CLAUDE.md
    sed -i "s|{{REPO_MAP_ROWS}}|${REPO_MAP_ROWS}|g" CLAUDE.md
else
    sed -i '/{{REPO_MAP_ROWS}}/d' CLAUDE.md
fi

# --- Initialize dependency map ---
cat > .claude/dependency-map.json << 'DEPEOF'
{
  "schema_version": 1,
  "edges": [],
  "repos": {}
}
DEPEOF

# --- Register child repos ---
if [[ -n "$REPOS" ]]; then
    IFS=',' read -ra REPO_PAIRS <<< "$REPOS"
    for pair in "${REPO_PAIRS[@]}"; do
        IFS=':' read -r name path <<< "$pair"
        name=$(echo "$name" | xargs)
        path=$(echo "$path" | xargs)
        if [[ -x "scripts/repos/register-repo.sh" ]]; then
            bash scripts/repos/register-repo.sh "$name" "$path" || echo "WARNING: Could not register ${name}"
        fi
    done
fi

# --- Write archetype manifest ---
ARCHETYPE_VERSION=$(cd "${ARCHETYPE_DIR}" && git rev-parse HEAD 2>/dev/null || echo "unknown")
cat > .archetype-manifest.json << MANEOF
{
  "archetype_origin": "${ARCHETYPE_DIR}",
  "archetype_version": "${ARCHETYPE_VERSION}",
  "init_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "template_values": {
    "PROJECT_NAME": "${PROJECT_NAME}",
    "PROJECT_ROOT": "${PROJECT_ROOT}",
    "MAINTAINER_EMAIL": "${MAINTAINER_EMAIL}"
  },
  "portable_paths": [
    "scripts/hooks/",
    "scripts/validate/",
    "scripts/utils/",
    "scripts/session/",
    "scripts/nightshift/",
    "scripts/repos/",
    "scripts/upstream/",
    "agents/shared/",
    "agents/*.md",
    "swarm/",
    ".claude/commands/",
    ".claude/skills/",
    "secrets/.secretpaths"
  ],
  "templated_files": [
    "CLAUDE.md",
    "README.md",
    "SPEC.md",
    "nightshift.yaml"
  ]
}
MANEOF

# --- Create .gitignore ---
cat > .gitignore << 'GIEOF'
# Logs
logs/*.log

# OS
.DS_Store
Thumbs.db

# Python
__pycache__/
*.pyc
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Swarm state (local to each machine)
swarm/*.db
swarm/*.db-wal
swarm/*.db-shm

# Session state (local, gitignored)
.session-identity
.session-stats
.push-logs.lock

# GitNexus indexes (rebuilt on demand)
.gitnexus/
AGENTS.md

# Local settings
.claude/settings.local.json

# Secrets (directory tracked, contents ignored)
secrets/*
!secrets/.gitkeep
!secrets/.secretpaths

# Archetype upstream manifest (instance-local)
.archetype-manifest.json
GIEOF

# --- Post-init validation ---
echo ""
echo "Running post-init validation..."
VALIDATION_FAILED=0

# Check required structure
for d in agents agents/shared scripts/hooks scripts/validate scripts/session scripts/utils \
         handoffs/active handoffs/completed .claude/commands .claude/skills swarm; do
    if [[ ! -d "$d" ]]; then
        echo "  WARN: Missing directory: $d"
        VALIDATION_FAILED=1
    fi
done

for f in CLAUDE.md .claude/settings.json .claude/maintainers.json .archetype-manifest.json; do
    if [[ ! -f "$f" ]]; then
        echo "  WARN: Missing file: $f"
        VALIDATION_FAILED=1
    fi
done

# Sandbox prerequisite check
if ! command -v bwrap &>/dev/null; then
    echo "  WARN: bubblewrap (bwrap) not installed. Sandbox will not work."
    echo "  Install: sudo apt install bubblewrap (Debian/Ubuntu)"
    echo "  Without sandbox, hooks cannot enforce OS-level read/write restrictions."
    VALIDATION_FAILED=1
fi

# Run validators if Python available
if command -v python3 &>/dev/null; then
    python3 scripts/validate/validate_agents_structure.py 2>/dev/null || VALIDATION_FAILED=1
    python3 scripts/validate/validate_agents_references.py 2>/dev/null || VALIDATION_FAILED=1
    python3 scripts/validate/validate_claude_md_consistency.py 2>/dev/null || VALIDATION_FAILED=1
    python3 scripts/validate/validate_document_drift.py 2>/dev/null || VALIDATION_FAILED=1
fi

if [[ $VALIDATION_FAILED -eq 0 ]]; then
    echo "Post-init validation passed"
else
    echo "Post-init validation completed with warnings (see above)"
fi

echo ""
echo "=== Project initialized: ${PROJECT_NAME} ==="
echo "Root: ${PROJECT_ROOT}"
echo ""
echo "Next steps:"
echo "  1. Review and customize CLAUDE.md"
echo "  2. Configure hooks in .claude/settings.json"
echo "  3. Add agent roles in agents/"
echo "  4. Register child repos: scripts/repos/register-repo.sh <name> <path>"
echo "  5. Index repos with GitNexus: npm install -g gitnexus && scripts/repos/sync-repos.sh --index"
echo "  6. Install bubblewrap for sandbox: sudo apt install bubblewrap"
echo "  7. Review secrets/.secretpaths and add project-specific protected paths"
