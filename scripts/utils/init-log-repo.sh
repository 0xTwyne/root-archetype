#!/bin/bash
set -euo pipefail

# Create a log repo for a root-archetype project.
# Called by init-project.sh or standalone for adding a log repo to an existing project.
#
# Usage: init-log-repo.sh <log-repo-path> <project-name> [--github]

usage() {
    echo "Usage: $0 <log-repo-path> <project-name> [--github]"
    echo ""
    echo "  log-repo-path   Where to create the log repo"
    echo "  project-name    Name of the parent governance project"
    echo "  --github        Create a GitHub repo via gh CLI"
    exit 1
}

[[ $# -lt 2 ]] && usage

LOG_REPO_PATH="$1"
PROJECT_NAME="$2"
shift 2

CREATE_GITHUB=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --github) CREATE_GITHUB=true; shift ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

LOG_REPO_NAME="${PROJECT_NAME}-logs"

echo "=== Creating log repo: ${LOG_REPO_NAME} ==="
echo "  Path: ${LOG_REPO_PATH}"

# --- Create directory and init git ---
mkdir -p "$LOG_REPO_PATH"
if [[ ! -d "${LOG_REPO_PATH}/.git" ]]; then
    git init "$LOG_REPO_PATH" >/dev/null
    git -C "$LOG_REPO_PATH" checkout -b main 2>/dev/null || true
fi

# --- Create directory structure ---
mkdir -p "$LOG_REPO_PATH/logs/audit" \
         "$LOG_REPO_PATH/logs/progress" \
         "$LOG_REPO_PATH/logs/skills" \
         "$LOG_REPO_PATH/notes/handoffs" \
         "$LOG_REPO_PATH/wiki"

touch "$LOG_REPO_PATH/logs/.gitkeep" \
      "$LOG_REPO_PATH/logs/audit/.gitkeep" \
      "$LOG_REPO_PATH/logs/progress/.gitkeep" \
      "$LOG_REPO_PATH/logs/skills/.gitkeep" \
      "$LOG_REPO_PATH/notes/.gitkeep" \
      "$LOG_REPO_PATH/notes/handoffs/.gitkeep" \
      "$LOG_REPO_PATH/wiki/.gitkeep" 2>/dev/null || true

# --- Write .gitignore ---
cat > "$LOG_REPO_PATH/.gitignore" << 'GIEOF'
# OS
.DS_Store
Thumbs.db

# Python
__pycache__/
*.pyc

# Session state (managed by root repo)
.session-identity
.session-stats
GIEOF

# --- Write README ---
cat > "$LOG_REPO_PATH/README.md" << READMEEOF
# ${LOG_REPO_NAME}

Log repository for the **${PROJECT_NAME}** governance workspace.

This repo stores session logs, progress reports, notes, handoffs, and per-member
wiki compilations. It is designed to be freely writable (no branch protections)
so that all team members can push logs without PR friction.

## Structure

\`\`\`
├── logs/
│   ├── audit/<user>/          # Per-user audit trails
│   ├── progress/<user>/       # Daily session progress reports
│   │   └── YYYY-MM-DD.md
│   ├── skills/                # Skill invocation logs
│   └── agent_audit.log        # Append-only audit trail (JSONL)
├── notes/
│   ├── <user>/
│   │   ├── plans/             # Session plans
│   │   ├── handoffs/          # Work tracking documents
│   │   │   ├── active/
│   │   │   └── completed/
│   │   └── facts.md           # Cross-session facts cache
│   └── handoffs/
│       └── INDEX.md           # Auto-generated aggregate index
└── wiki/
    └── <user>/                # Per-member wiki compilations
\`\`\`

## Conventions

- **Append-only**: logs and progress reports are never overwritten, only appended
- **User isolation**: each user writes only to their own directories
- **Provenance**: all artifacts include source repo and branch context
- **Auto-push**: the session-end hook commits and pushes automatically

## Relationship to Root Repo

The governance root repo (\`${PROJECT_NAME}\`) contains the master wiki, agent
definitions, hooks, and scripts. This log repo is registered as a child repo
in the root's \`repos/\` directory.

Master wiki compilation (by maintainers) reads from this repo and writes to
the root repo's \`knowledge/wiki/\`.
READMEEOF

# --- Initial commit ---
cd "$LOG_REPO_PATH"
git add -A 2>/dev/null || true
git commit -m "init: log repo for ${PROJECT_NAME}" 2>/dev/null || true

# --- Optional GitHub repo ---
if [[ "$CREATE_GITHUB" == true ]] && command -v gh &>/dev/null; then
    echo "  Creating GitHub repo: ${LOG_REPO_NAME}..."
    gh repo create "${LOG_REPO_NAME}" --private --source=. --push 2>/dev/null \
        && echo "  GitHub repo created: ${LOG_REPO_NAME}" \
        || echo "  NOTE: Could not create GitHub repo for logs."
fi

echo "Log repo created: ${LOG_REPO_PATH}"

# Print absolute path for callers
cd "$LOG_REPO_PATH" && pwd -P
