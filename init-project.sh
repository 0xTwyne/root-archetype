#!/bin/bash
set -euo pipefail

# Root-Archetype Project Initializer
# Usage: ./init-project.sh <project-name> [options]
#
# Default: in-place init (CWD is the cloned archetype, transforms in place)
# Legacy:  --copy-to <path>  copies archetype to a new directory

usage() {
    cat <<'USAGE'
Usage: init-project.sh <project-name> [options]

Options:
  --copy-to <path>   Copy archetype to target (default: in-place)
  --engine <name>    Reasoning engine (claude, codex; default: claude)
  --guided           Drop .needs-init marker for interactive wizard
  --repos <list>     Comma-separated child repos (name:path pairs)
  --description <d>  Short project description
  --log-repo <path>  Custom log repo path (default: repos/<name>-logs)
  --force            Allow init with uncommitted changes

Examples:
  git clone <archetype> my-project && cd my-project
  ./init-project.sh my-project --guided
  ./init-project.sh my-project --copy-to /path/to/target
USAGE
    exit 1
}

[[ $# -lt 1 ]] && usage

PROJECT_NAME="$1"; shift
COPY_TO="" REPOS="" GUIDED=false ENGINE="claude" DESCRIPTION="" FORCE=false LOG_REPO_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --copy-to) COPY_TO="$2"; shift 2 ;;
        --engine) ENGINE="$2"; shift 2 ;;
        --guided) GUIDED=true; shift ;;
        --repos) REPOS="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --log-repo) LOG_REPO_OVERRIDE="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

ARCHETYPE_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -d "${ARCHETYPE_DIR}/agents/engines/${ENGINE}" ]] || \
    { echo "Error: Unknown engine '${ENGINE}'."; ls -1 "${ARCHETYPE_DIR}/agents/engines" | grep -v README; exit 1; }

# --- Auto-detect user identity ---
GH_USER=""; MAINTAINER_EMAIL=""
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    GH_USER="$(gh api user --jq '.login' 2>/dev/null || true)"
    MAINTAINER_EMAIL="$(gh api user --jq '.email // empty' 2>/dev/null || true)"
fi
[[ -z "$MAINTAINER_EMAIL" ]] && MAINTAINER_EMAIL="$(git config user.email 2>/dev/null || true)"
[[ -z "$MAINTAINER_EMAIL" ]] && { echo "ERROR: Cannot detect email. Set git config user.email"; exit 1; }

# Capture archetype version before we might wipe .git
ARCHETYPE_VERSION="$(cd "${ARCHETYPE_DIR}" && git rev-parse HEAD 2>/dev/null || echo unknown)"

# --- Populate project directory ---
if [[ -z "$COPY_TO" ]]; then
    # In-place: CWD is the cloned archetype
    [[ -d "${ARCHETYPE_DIR}/agents/shared" && -d "${ARCHETYPE_DIR}/scripts/hooks" ]] || \
        { echo "ERROR: CWD does not look like a root-archetype clone."; exit 1; }
    if [[ "$FORCE" != true && -d "${ARCHETYPE_DIR}/.git" ]]; then
        [[ -z "$(git -C "$ARCHETYPE_DIR" diff --name-only HEAD 2>/dev/null)" ]] || \
            { echo "ERROR: Uncommitted changes. Commit/stash first, or use --force."; exit 1; }
    fi
    PROJECT_ROOT="$ARCHETYPE_DIR"
    rm -rf "${PROJECT_ROOT}/.git"
    git init "$PROJECT_ROOT" >/dev/null
    git -C "$PROJECT_ROOT" checkout -b main 2>/dev/null || true
    # Clean instance-specific data from in-place clone
    rm -f notes/handoffs/INDEX.md logs/progress/*/*.md 2>/dev/null || true
else
    # Copy mode: clone archetype tree to target
    PROJECT_ROOT="$COPY_TO"
    mkdir -p "$PROJECT_ROOT"
    if [[ ! -d "${PROJECT_ROOT}/.git" ]]; then
        git init "$PROJECT_ROOT" >/dev/null
        git -C "$PROJECT_ROOT" checkout -b main 2>/dev/null || true
    fi
    # Copy tracked content, excluding instance-specific data
    (cd "$ARCHETYPE_DIR" && git ls-files -z 2>/dev/null || find . -type f -not -path './.git/*' -print0) | \
        grep -zvE '^(logs/progress/|notes/.*/handoffs/|notes/handoffs/INDEX)' | \
        (cd "$ARCHETYPE_DIR" && xargs -0 -I{} bash -c 'mkdir -p "'"$PROJECT_ROOT"'/$(dirname "{}")" && cp "{}" "'"$PROJECT_ROOT"'/{}"')
    chmod +x "$PROJECT_ROOT"/scripts/**/*.sh "$PROJECT_ROOT"/scripts/**/*.py 2>/dev/null || true
fi

echo "=== Root-Archetype Project Initializer ==="
echo "Project: ${PROJECT_NAME} | Mode: $([[ -z "$COPY_TO" ]] && echo in-place || echo copy)"
echo "Engine: ${ENGINE} | User: ${MAINTAINER_EMAIL}${GH_USER:+ (${GH_USER})}"

cd "$PROJECT_ROOT"

# --- Template substitution ---
substitute() {
    sed -i -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
           -e "s|{{PROJECT_ROOT}}|${PROJECT_ROOT}|g" \
           -e "s|{{MAINTAINER_EMAIL}}|${MAINTAINER_EMAIL}|g" \
           -e "s|{{DESCRIPTION}}|${DESCRIPTION}|g" "$1"
}
for f in AGENT.md README.md MAINTAINERS.json .devcontainer/devcontainer.json; do
    [[ -f "$f" ]] && substitute "$f"
done

# --- Generate engine adapter files ---
bash scripts/utils/generate-engine.sh --engine "$ENGINE" --project-dir "$(pwd)"

# --- Ensure directory structure ---
# logs/ and notes/ are skeletal stubs in root — actual data lives in the log repo
mkdir -p knowledge/wiki knowledge/research/deep-dives \
         logs notes local repos secrets 2>/dev/null || true
touch knowledge/wiki/.gitkeep knowledge/research/.gitkeep \
      knowledge/research/deep-dives/.gitkeep \
      local/.gitkeep repos/.gitkeep secrets/.gitkeep 2>/dev/null || true

# --- Create log repo ---
LOG_REPO_NAME="${PROJECT_NAME}-logs"
LOG_REPO_PATH="${LOG_REPO_OVERRIDE:-$(pwd)/repos/${LOG_REPO_NAME}}"
echo ""
echo "Creating log repo: ${LOG_REPO_NAME}"
echo "  Path: ${LOG_REPO_PATH} $([[ -z "$LOG_REPO_OVERRIDE" ]] && echo "(default)" || echo "(custom)")"

GITHUB_FLAG=""
[[ -n "$GH_USER" ]] && command -v gh &>/dev/null && GITHUB_FLAG="--github"
bash scripts/utils/init-log-repo.sh "$LOG_REPO_PATH" "$PROJECT_NAME" $GITHUB_FLAG 2>/dev/null || {
    echo "WARNING: Log repo creation failed at ${LOG_REPO_PATH}"
}

# Register log repo as a child repo (no agent scaffolding — infrastructure repo)
if [[ -d "$LOG_REPO_PATH" ]]; then
    bash scripts/repos/register-repo.sh "$LOG_REPO_NAME" "$LOG_REPO_PATH" \
        --purpose "Session logs, notes, handoffs, per-member wikis" \
        --no-scaffold 2>/dev/null || true
fi

# Add log repo directory to .gitignore (prevent parent from tracking nested repo content)
if ! grep -qF "repos/${LOG_REPO_NAME}/" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Log repo (nested git repo — content tracked separately)" >> .gitignore
    echo "repos/${LOG_REPO_NAME}/" >> .gitignore
fi

# Write stub READMEs for skeletal logs/ and notes/ in root
cat > logs/README.md << 'STUBEOF'
# Logs

Session logs, audit trails, and progress reports live in the **log repo**.

The log repo is registered as a child repo in `repos/`. To find the path:

```bash
jq -r '.log_repo_name' .archetype-manifest.json
# Then look in repos/<name>/
```

This directory exists as a stub for documentation only.
STUBEOF

cat > notes/README.md << 'STUBEOF'
# Notes

Per-user notes, handoffs, plans, and facts live in the **log repo**.

The log repo is registered as a child repo in `repos/`. To find the path:

```bash
jq -r '.log_repo_name' .archetype-manifest.json
# Then look in repos/<name>/
```

This directory exists as a stub for documentation only.
STUBEOF

# --- Create GitHub repo (if gh available) ---
if [[ -n "$GH_USER" ]] && command -v gh &>/dev/null; then
    echo "Creating GitHub repo: ${GH_USER}/${PROJECT_NAME}..."
    gh repo create "${PROJECT_NAME}" --private --source=. --push 2>/dev/null \
        && echo "Origin set to: https://github.com/${GH_USER}/${PROJECT_NAME}" \
        || echo "NOTE: Could not create GitHub repo. Set origin manually."
else
    echo "NOTE: gh CLI not available. Set origin manually: git remote add origin <url>"
fi

# --- Register child repos ---
REPO_MAP_ROWS=""
if [[ -n "$REPOS" ]]; then
    IFS=',' read -ra REPO_PAIRS <<< "$REPOS"
    for pair in "${REPO_PAIRS[@]}"; do
        IFS=':' read -r name path <<< "$pair"
        name=$(echo "$name" | xargs); path=$(echo "$path" | xargs)
        REPO_MAP_ROWS+="| ${name} | \`${path}\` | (configure purpose) |\\n"
        [[ -x scripts/repos/register-repo.sh ]] && \
            bash scripts/repos/register-repo.sh "$name" "$path" 2>/dev/null || true
    done
    sed -i "s|{{REPO_MAP_ROWS}}|${REPO_MAP_ROWS}|g" AGENT.md 2>/dev/null || true
else
    sed -i '/{{REPO_MAP_ROWS}}/d' AGENT.md 2>/dev/null || true
fi

# --- Write archetype manifest ---
cat > .archetype-manifest.json << MANEOF
{
  "engine": "${ENGINE}",
  "archetype_origin": "${ARCHETYPE_DIR}",
  "archetype_version": "${ARCHETYPE_VERSION}",
  "init_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "log_repo_name": "${LOG_REPO_NAME}",
  "template_values": {
    "PROJECT_NAME": "${PROJECT_NAME}",
    "PROJECT_ROOT": "${PROJECT_ROOT}",
    "MAINTAINER_EMAIL": "${MAINTAINER_EMAIL}",
    "GH_USER": "${GH_USER}",
    "description": "${DESCRIPTION}"
  }
}
MANEOF

# --- Guided mode: drop .needs-init marker ---
if [[ "$GUIDED" == true ]]; then
    cat > .needs-init << INITEOF
{
  "project_name": "${PROJECT_NAME}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "init_mode": "guided",
  "steps_remaining": ["description", "repos", "detect-maintainers", "child-agents", "maintainer", "hooks", "knowledge", "roles", "finalize"]
}
INITEOF
    echo ""
    echo "Guided mode: .needs-init marker created."
    echo "Start a Claude or Codex session to complete setup with the init wizard."
fi

# --- Generate README (non-guided mode) ---
if [[ "$GUIDED" != true ]] && [[ -x scripts/utils/generate-readme.sh ]]; then
    bash scripts/utils/generate-readme.sh --project-dir "$(pwd)" 2>/dev/null || true
fi

# --- Post-init validation ---
echo ""; WARN=0
for check in agents:d agents/engines:d scripts/hooks:d AGENT.md:f MAINTAINERS.json:f; do
    path="${check%%:*}"; type="${check##*:}"
    [[ ("$type" == d && -d "$path") || ("$type" == f && -f "$path") ]] || { echo "  WARN: Missing $path"; WARN=1; }
done
# Validate log repo
if [[ -d "$LOG_REPO_PATH/.git" ]]; then
    echo "  Log repo: OK (repos/${LOG_REPO_NAME}/)"
else
    echo "  WARN: Log repo not found at ${LOG_REPO_PATH}"; WARN=1
fi
[[ "$ENGINE" == claude ]] && for f in CLAUDE.md .claude/settings.json; do
    [[ -f "$f" ]] || { echo "  WARN: Missing $f"; WARN=1; }
done
[[ "$ENGINE" == codex ]] && [[ -f CODEX.md ]] || { [[ "$ENGINE" != codex ]] || { echo "  WARN: Missing CODEX.md"; WARN=1; }; }
[[ $WARN -eq 0 ]] && echo "Validation passed." || echo "Validation completed with warnings."
echo ""
echo "=== Initialized: ${PROJECT_NAME} (engine: ${ENGINE}) ==="
echo "  Root repo: ${PROJECT_ROOT}"
echo "  Log repo:  ${LOG_REPO_PATH}"
