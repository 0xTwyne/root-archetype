#!/bin/bash
set -euo pipefail

# Retroactive Manifest Generator
# Generates .archetype-manifest.json for instances created before this feature existed.
# Run from inside a live root repo instance.

usage() {
    echo "Usage: $0 [--archetype-path /path/to/root-archetype]"
    echo ""
    echo "  Generates .archetype-manifest.json for this root repo instance."
    echo "  If --archetype-path is not provided, attempts auto-detection."
    exit 1
}

ARCHETYPE_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --archetype-path)
            ARCHETYPE_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

INSTANCE_ROOT="$(pwd)"

# --- Validate we're in a root repo instance ---
if [[ ! -f "CLAUDE.md" ]]; then
    echo "ERROR: No CLAUDE.md found. Are you in a root repo instance?"
    exit 1
fi

if [[ -f ".archetype-manifest.json" ]]; then
    echo "WARNING: .archetype-manifest.json already exists."
    read -rp "Overwrite? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# --- Auto-detect archetype path ---
if [[ -z "$ARCHETYPE_PATH" ]]; then
    # Check sibling directories
    PARENT_DIR="$(dirname "$INSTANCE_ROOT")"
    for candidate in "$PARENT_DIR/root-archetype" "$PARENT_DIR/archetype"; do
        if [[ -d "$candidate" && -f "$candidate/init-project.sh" ]]; then
            ARCHETYPE_PATH="$candidate"
            echo "Auto-detected archetype at: $ARCHETYPE_PATH"
            break
        fi
    done
fi

if [[ -z "$ARCHETYPE_PATH" ]]; then
    echo "Could not auto-detect archetype path."
    read -rp "Enter path to root-archetype: " ARCHETYPE_PATH
fi

ARCHETYPE_PATH="$(cd "$ARCHETYPE_PATH" && pwd)"

if [[ ! -f "$ARCHETYPE_PATH/init-project.sh" ]]; then
    echo "ERROR: $ARCHETYPE_PATH does not look like root-archetype (no init-project.sh)"
    exit 1
fi

# --- Extract PROJECT_NAME from CLAUDE.md header ---
# Looks for "# ProjectName —" pattern
PROJECT_NAME=$(head -5 CLAUDE.md | grep -oP '^#\s+\K[^\s—]+' | head -1 || true)
if [[ -z "$PROJECT_NAME" ]]; then
    read -rp "Could not detect PROJECT_NAME from CLAUDE.md. Enter it: " PROJECT_NAME
fi

PROJECT_ROOT="$INSTANCE_ROOT"

# --- Find closest matching archetype commit ---
ARCHETYPE_VERSION="unknown"
if command -v git &>/dev/null && [[ -d "$ARCHETYPE_PATH/.git" ]]; then
    # Use the archetype's current HEAD as best approximation
    ARCHETYPE_VERSION=$(cd "$ARCHETYPE_PATH" && git rev-parse HEAD 2>/dev/null || echo "unknown")
    echo "Using archetype version: $ARCHETYPE_VERSION (current HEAD)"
fi

# --- Write manifest ---
cat > .archetype-manifest.json << MANEOF
{
  "archetype_origin": "${ARCHETYPE_PATH}",
  "archetype_version": "${ARCHETYPE_VERSION}",
  "init_date": "retroactive",
  "template_values": {
    "PROJECT_NAME": "${PROJECT_NAME}",
    "PROJECT_ROOT": "${PROJECT_ROOT}"
  },
  "portable_paths": [
    "scripts/hooks/",
    "scripts/validate/",
    "scripts/utils/",
    "scripts/session/",
    "scripts/nightshift/",
    "scripts/repos/",
    "agents/shared/",
    "agents/*.md",
    "swarm/",
    ".claude/commands/",
    ".claude/skills/"
  ],
  "templated_files": [
    "CLAUDE.md",
    "README.md",
    "SPEC.md",
    "nightshift.yaml"
  ]
}
MANEOF

# --- Ensure manifest is gitignored ---
if [[ -f ".gitignore" ]]; then
    if ! grep -qF '.archetype-manifest.json' .gitignore; then
        echo "" >> .gitignore
        echo "# Archetype upstream manifest (instance-local)" >> .gitignore
        echo ".archetype-manifest.json" >> .gitignore
        echo "Added .archetype-manifest.json to .gitignore"
    fi
fi

echo ""
echo "=== Manifest created: .archetype-manifest.json ==="
echo "Project: ${PROJECT_NAME}"
echo "Root:    ${PROJECT_ROOT}"
echo "Origin:  ${ARCHETYPE_PATH}"
echo ""
echo "You can now run: scripts/upstream/distill.sh"
