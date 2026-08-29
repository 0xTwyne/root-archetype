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

# Name follows the path — init-project.sh chooses the path (default
# repos/<project>-knowledge), and forcing a different name here is how the
# registered name used to desync from the directory.
LOG_REPO_NAME="$(basename "$LOG_REPO_PATH")"

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
         "$LOG_REPO_PATH/research/deep-dives" \
         "$LOG_REPO_PATH/wiki"

touch "$LOG_REPO_PATH/logs/.gitkeep" \
      "$LOG_REPO_PATH/logs/audit/.gitkeep" \
      "$LOG_REPO_PATH/logs/progress/.gitkeep" \
      "$LOG_REPO_PATH/logs/skills/.gitkeep" \
      "$LOG_REPO_PATH/notes/.gitkeep" \
      "$LOG_REPO_PATH/notes/handoffs/.gitkeep" \
      "$LOG_REPO_PATH/research/deep-dives/.gitkeep" \
      "$LOG_REPO_PATH/wiki/.gitkeep" 2>/dev/null || true

# --- Seed wiki schema, index builder, and facts cache ---
# The wiki is structured the same way logs/ and notes/ are: this script owns
# the layout, so a new project starts with somewhere obvious to put each kind
# of article rather than an empty directory and a guess. The log repo also owns
# its own indexing, so it ships with the builder and the frontmatter spec that
# builder reads.
WIKI_CATEGORIES=(concepts repos operations research incidents tooling)
for _c in "${WIKI_CATEGORIES[@]}"; do
    mkdir -p "$LOG_REPO_PATH/wiki/$_c"
    touch "$LOG_REPO_PATH/wiki/$_c/.gitkeep" 2>/dev/null || true
done

ARCHETYPE_DIR="${ARCHETYPE_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEMPLATE_DIR="$ARCHETYPE_DIR/templates/log-repo"

# Every copy below is REQUIRED, and each is checked. These used to be
# `cp ... 2>/dev/null || true`, which meant a missing or unreadable template
# produced a log repo silently lacking its index builder, its frontmatter spec,
# or its agent instructions — discovered much later, if at all.
if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "ERROR: template directory not found at $TEMPLATE_DIR" >&2
    echo "  The log repo would be created without its builder, schema or AGENT.md." >&2
    exit 1
fi

mkdir -p "$LOG_REPO_PATH/scripts"
copy_required() {
    local src="$1" dst="$2"
    if [[ ! -f "$src" ]]; then
        echo "ERROR: required template missing: $src" >&2
        return 1
    fi
    cp "$src" "$dst" || { echo "ERROR: could not copy $src -> $dst" >&2; return 1; }
}
COPY_FAILED=0
copy_required "$TEMPLATE_DIR/scripts/build-indexes.sh" "$LOG_REPO_PATH/scripts/build-indexes.sh" || COPY_FAILED=1
copy_required "$TEMPLATE_DIR/wiki/schema.md"           "$LOG_REPO_PATH/wiki/schema.md"           || COPY_FAILED=1
copy_required "$TEMPLATE_DIR/wiki/README.md"           "$LOG_REPO_PATH/wiki/README.md"           || COPY_FAILED=1
copy_required "$TEMPLATE_DIR/wiki/taxonomy.yaml"        "$LOG_REPO_PATH/wiki/taxonomy.yaml"       || COPY_FAILED=1
copy_required "$TEMPLATE_DIR/research/intake_index.yaml" "$LOG_REPO_PATH/research/intake_index.yaml" || COPY_FAILED=1
[[ "$COPY_FAILED" -eq 0 ]] || { echo "ERROR: log repo is incomplete — aborting rather than shipping a broken one." >&2; exit 1; }

# AGENT.md — the rules for writing to and pushing this repo. A log repo without
# it is one an agent has no repo-local instructions for, which is how conventions
# like append-only and user isolation get broken by someone acting in good faith.
if [[ -f "$TEMPLATE_DIR/AGENT.md.tmpl" ]]; then
    sed -e "s|{{LOG_REPO_NAME}}|${LOG_REPO_NAME}|g" \
        -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
        "$TEMPLATE_DIR/AGENT.md.tmpl" > "$LOG_REPO_PATH/AGENT.md" \
        || { echo "ERROR: could not write AGENT.md" >&2; exit 1; }
else
    echo "ERROR: required template missing: $TEMPLATE_DIR/AGENT.md.tmpl" >&2
    exit 1
fi

# identities.json — the alias registry. Ships empty; each person registers on
# their first session. Without it, one human resolves to a different directory
# depending on whether gh happened to be authenticated, and their history splits.
if [[ -f "$TEMPLATE_DIR/identities.json.tmpl" ]]; then
    sed -e "s|{{LOG_REPO_NAME}}|${LOG_REPO_NAME}|g" \
        -e "s|{{PROJECT_NAME}}|${PROJECT_NAME}|g" \
        "$TEMPLATE_DIR/identities.json.tmpl" > "$LOG_REPO_PATH/identities.json" \
        || { echo "ERROR: could not write identities.json" >&2; exit 1; }
else
    echo "ERROR: required template missing: $TEMPLATE_DIR/identities.json.tmpl" >&2
    exit 1
fi

# Runtime state the knowledge repo must never track: the compile watermark and
# the per-machine session marker (tracking the latter once pushed one machine's
# session id into every clone).
if [[ ! -f "$LOG_REPO_PATH/.gitignore" ]]; then
    printf '%s\n' \
        "# Compile watermark — per-clone runtime state" \
        ".last_compile" \
        "# Which session is active on THIS machine — never track" \
        "logs/.current_session" \
        > "$LOG_REPO_PATH/.gitignore"
fi

# facts.md is per-user and created on first session by the session-start hook.
# The template is kept for reference rather than copied in as a stray .tmpl file.

chmod +x "$LOG_REPO_PATH/scripts/build-indexes.sh"

# Generate INDEX.md and STALENESS.md now, so they exist from the first commit
# and nobody mistakes their absence for a broken build. Report failure — a
# builder that cannot run on an empty repo is a day-one bug worth knowing about.
if ! ( cd "$LOG_REPO_PATH" && bash scripts/build-indexes.sh >/dev/null 2>&1 ); then
    echo "WARNING: build-indexes.sh failed on the freshly created log repo." >&2
    echo "  This usually means it does not handle the empty/day-one case." >&2
fi

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
└── wiki/                      # Compiled knowledge, shared across users
    ├── schema.md              # Frontmatter spec and tag vocabulary
    ├── INDEX.md               # Auto-generated catalog + scope lookup
    ├── STALENESS.md           # Auto-generated; articles whose sources moved
    ├── concepts/              # Domain concepts and mechanics
    ├── repos/                 # Per-repo architecture and conventions
    ├── operations/            # Procedures, onboarding, governance
    ├── research/              # Findings and methodology
    ├── incidents/             # Post-incident knowledge
    └── tooling/               # Tool and process documentation
\`\`\`

## Conventions

- **Append-only**: logs and progress reports are never overwritten, only appended
- **User isolation**: each user writes only to their own directories
- **Provenance**: all artifacts include source repo and branch context
- **Auto-push**: the session-end hook commits and pushes automatically

## Relationship to Root Repo

The governance root repo (\`${PROJECT_NAME}\`) contains the agent definitions,
hooks, and scripts. This log repo is registered as a child repo in the root's
\`repos/\` directory.

The compiled wiki lives **here**, in \`wiki/\`, alongside the per-user streams it
is compiled from — so an article and its sources stay in one repo. Compile with
\`/project-wiki compile\`; regenerate the indexes with
\`bash scripts/build-indexes.sh\`, which also runs from the governance root
through a thin wrapper of the same name.
READMEEOF

# --- Initial commit ---
cd "$LOG_REPO_PATH"
# A masked failure here leaves the log repo with no initial commit, and the
# later `gh repo create --push` then fails confusingly. Report it loudly
# (but keep going: the rest of init is still useful).
git add -A || echo "WARNING: git add failed in ${LOG_REPO_PATH}" >&2
if ! git commit -q -m "init: log repo for ${PROJECT_NAME}"; then
    echo "WARNING: initial commit failed in ${LOG_REPO_PATH} (check git identity config) — repo has no initial commit" >&2
fi

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
