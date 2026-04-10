#!/bin/bash
set -euo pipefail

# Root-Archetype Project Initializer
# Usage: ./init-project.sh <project-name> <target-path> [--guided] [--repos "n:p,..."] [--email "x"]

usage() {
    echo "Usage: $0 <project-name> <target-path> [options]"
    echo ""
    echo "Options:"
    echo "  --guided   Drop .needs-init marker for interactive wizard"
    echo "  --repos    Comma-separated child repos (name:path pairs)"
    echo "  --email    Maintainer email"
    echo ""
    echo "Example: $0 my-project /tmp/test --repos \"app:/tmp/app\" --email \"dev@co.com\""
    exit 1
}

[[ $# -lt 2 ]] && usage

PROJECT_NAME="$1"
PROJECT_ROOT="$2"
shift 2

REPOS="" MAINTAINER_EMAIL="" GUIDED=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --guided) GUIDED=true; shift ;;
        --repos) REPOS="$2"; shift 2 ;;
        --email) MAINTAINER_EMAIL="$2"; shift 2 ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

ARCHETYPE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Root-Archetype Project Initializer ==="
echo "Project: ${PROJECT_NAME} | Root: ${PROJECT_ROOT} | Mode: $([[ $GUIDED == true ]] && echo guided || echo quick)"

# --- Create project and init git ---
mkdir -p "${PROJECT_ROOT}"
if [[ ! -d "${PROJECT_ROOT}/.git" ]]; then
    git init "${PROJECT_ROOT}" >/dev/null
    git -C "${PROJECT_ROOT}" checkout -b main 2>/dev/null || true
fi
cd "${PROJECT_ROOT}"

# --- Template substitution ---
substitute() {
    sed -i -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
           -e "s|{{PROJECT_ROOT}}|${PROJECT_ROOT}|g" \
           -e "s|{{MAINTAINER_EMAIL}}|${MAINTAINER_EMAIL}|g" "$1"
}

# --- Copy directory tree (files only, preserving structure) ---
copy_tree() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || return 0
    find "$src" -type f | while read -r f; do
        local rel="${f#$src/}"
        mkdir -p "$(dirname "${dst}/${rel}")"
        cp "$f" "${dst}/${rel}"
    done
}

# --- Copy and substitute a single file ---
copy_sub() {
    local src="${ARCHETYPE_DIR}/$1" dst="$2"
    [[ -f "$src" ]] || return 0
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    substitute "$dst"
}

# --- Create directory structure ---
mkdir -p agents/{shared,roles,skills} scripts/{hooks,validate,session,utils,repos} \
         .claude/skills notes knowledge/{wiki,research/deep-dives} logs local repos secrets .devcontainer

# --- Copy core governance files ---
for f in AGENT.md CLAUDE.md CODEX.md README.md MAINTAINERS.json .gitignore; do
    copy_sub "$f" "$f"
done

# --- Copy agent system ---
copy_tree "${ARCHETYPE_DIR}/agents" agents

# --- Copy scripts ---
copy_tree "${ARCHETYPE_DIR}/scripts/hooks" scripts/hooks
copy_tree "${ARCHETYPE_DIR}/scripts/validate" scripts/validate
copy_tree "${ARCHETYPE_DIR}/scripts/session" scripts/session
copy_tree "${ARCHETYPE_DIR}/scripts/utils" scripts/utils
copy_tree "${ARCHETYPE_DIR}/scripts/repos" scripts/repos
chmod +x scripts/hooks/*.sh scripts/validate/*.py scripts/session/*.sh \
         scripts/utils/*.sh scripts/repos/*.sh 2>/dev/null || true

# --- Copy Claude Code config ---
copy_sub ".claude/settings.json" ".claude/settings.json"
copy_tree "${ARCHETYPE_DIR}/.claude/skills" .claude/skills
copy_tree "${ARCHETYPE_DIR}/.claude/hooks" .claude/hooks
chmod +x .claude/hooks/*.sh 2>/dev/null || true

# --- Copy supporting files ---
copy_sub ".devcontainer/devcontainer.json" ".devcontainer/devcontainer.json"
copy_sub "secrets/.secretpaths" "secrets/.secretpaths"
copy_sub "notes/README.md" "notes/README.md"
copy_sub "knowledge/taxonomy.yaml" "knowledge/taxonomy.yaml"
copy_sub "knowledge/research/intake_index.yaml" "knowledge/research/intake_index.yaml"

# --- Gitkeep empty dirs ---
touch knowledge/wiki/.gitkeep knowledge/research/.gitkeep \
      knowledge/research/deep-dives/.gitkeep logs/.gitkeep \
      local/.gitkeep repos/.gitkeep secrets/.gitkeep

# --- Build repo map and register ---
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
  "archetype_origin": "${ARCHETYPE_DIR}",
  "archetype_version": "$(cd "${ARCHETYPE_DIR}" && git rev-parse HEAD 2>/dev/null || echo unknown)",
  "init_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "template_values": {
    "PROJECT_NAME": "${PROJECT_NAME}",
    "PROJECT_ROOT": "${PROJECT_ROOT}",
    "MAINTAINER_EMAIL": "${MAINTAINER_EMAIL}"
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
  "steps_remaining": ["repos", "child-agents", "maintainer", "hooks", "knowledge", "roles"]
}
INITEOF
    echo ""
    echo "Guided mode: .needs-init marker created."
    echo "Start a Claude or Codex session to complete setup with the init wizard."
fi

# --- Post-init validation ---
echo ""
WARN=0
for d in agents scripts/hooks .claude/skills; do
    [[ -d "$d" ]] || { echo "  WARN: Missing $d"; WARN=1; }
done
for f in AGENT.md CLAUDE.md .claude/settings.json MAINTAINERS.json; do
    [[ -f "$f" ]] || { echo "  WARN: Missing $f"; WARN=1; }
done
[[ $WARN -eq 0 ]] && echo "Validation passed." || echo "Validation completed with warnings."

echo ""
echo "=== Project initialized: ${PROJECT_NAME} ==="
echo "Next: review AGENT.md, configure hooks, register child repos."
