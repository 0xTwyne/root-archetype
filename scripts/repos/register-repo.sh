#!/bin/bash
set -euo pipefail

# Register a child repo with the root governance repo
# Usage: register-repo.sh <name> <path> [--purpose "description"]

usage() {
    echo "Usage: $0 <name> <path> [--purpose \"description\"] [--no-scaffold]"
    echo ""
    echo "  name           Short identifier for the repo"
    echo "  path           Absolute path to the repo"
    echo "  --purpose      Optional description of the repo's role"
    echo "  --no-scaffold  Skip agent file seeding (for infrastructure repos)"
    exit 1
}

[[ $# -lt 2 ]] && usage

REPO_NAME="$1"
REPO_PATH="$2"
shift 2

PURPOSE=""
NO_SCAFFOLD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purpose) PURPOSE="$2"; shift 2 ;;
        --no-scaffold) NO_SCAFFOLD=true; shift ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"
REPOS_DIR="${ROOT_DIR}/repos"

# Source logging if available
if [[ -f "${ROOT_DIR}/scripts/utils/agent_log.sh" ]]; then
    source "${ROOT_DIR}/scripts/utils/agent_log.sh"
    agent_task_start "Register repo: ${REPO_NAME}" "Path: ${REPO_PATH}"
fi

echo "=== Registering repo: ${REPO_NAME} ==="

# --- Validate path ---
if [[ ! -d "$REPO_PATH" ]]; then
    echo "WARNING: Path ${REPO_PATH} does not exist yet. Registering anyway."
fi

# --- Register in repos/ ---
mkdir -p "$REPOS_DIR"
REPO_ABS="$(cd "$REPO_PATH" 2>/dev/null && pwd -P || echo "$REPO_PATH")"
REPOS_ABS="$(cd "$REPOS_DIR" 2>/dev/null && pwd -P)"

if [[ "$REPO_ABS" == "$REPOS_ABS"/* ]]; then
    # Repo already lives inside repos/ — no symlink needed
    echo "Registered: repos/${REPO_NAME} (physical directory)"
else
    # External repo — create symlink
    if [[ -L "${REPOS_DIR}/${REPO_NAME}" ]]; then
        echo "Symlink already exists, updating..."
        rm "${REPOS_DIR}/${REPO_NAME}"
    fi
    ln -s "$REPO_PATH" "${REPOS_DIR}/${REPO_NAME}"
    echo "Linked: repos/${REPO_NAME} -> ${REPO_PATH}"
fi

# --- Update AGENT.md repository map ---
AGENT_MD="${ROOT_DIR}/AGENT.md"
if [[ -f "$AGENT_MD" ]]; then
    ROW="| ${REPO_NAME} | \`${REPO_PATH}\` | ${PURPOSE:-(configure purpose)} |"
    if ! grep -qF "| ${REPO_NAME} |" "$AGENT_MD" 2>/dev/null; then
        # Append row after the repo map header
        sed -i "/{{REPO_MAP_ROWS}}/a\\${ROW}" "$AGENT_MD" 2>/dev/null || \
        sed -i "/^|.*Path.*Purpose/a\\${ROW}" "$AGENT_MD" 2>/dev/null || true
    fi
fi

# --- Seed agent files if missing (skip for infrastructure repos) ---
if [[ "$NO_SCAFFOLD" != true ]] && [[ -d "$REPO_PATH" ]]; then
    if [[ ! -f "${REPO_PATH}/CLAUDE.md" ]]; then
        cat > "${REPO_PATH}/CLAUDE.md" << CLAUDE_EOF
# ${REPO_NAME}

## Purpose

${PURPOSE:-Configure this repo's purpose.}

## Code Style

- Follow existing project conventions
- Run validation after producing artifacts
CLAUDE_EOF
        echo "Seeded: ${REPO_PATH}/CLAUDE.md"
    fi

    if [[ ! -d "${REPO_PATH}/agents" ]]; then
        mkdir -p "${REPO_PATH}/agents"
        cat > "${REPO_PATH}/agents/developer.md" << AGENT_EOF
# Developer

## Mission
General development work for ${REPO_NAME}.

## Use This Role When
- Implementing features or fixes in this repo

## Inputs Required
- Task description or issue reference

## Outputs
- Code changes with tests

## Workflow
1. Understand the task
2. Implement and test
3. Document

## Guardrails
- Follow project code style
- Run tests before committing
AGENT_EOF
        echo "Seeded: ${REPO_PATH}/agents/developer.md"
    else
        echo "Agent files already exist in ${REPO_PATH}/agents/"
    fi
fi

# --- Auto-detect maintainers from child repo ---
DETECT_SCRIPT="${ROOT_DIR}/scripts/utils/detect-maintainers.sh"
if [[ -x "$DETECT_SCRIPT" ]] && [[ -d "$REPO_PATH" ]]; then
    DETECTED="$(bash "$DETECT_SCRIPT" "$REPO_NAME" "$REPO_PATH" 2>/dev/null || echo "")"
    if [[ -n "$DETECTED" ]] && [[ "$DETECTED" != "{}" ]] && command -v jq &>/dev/null; then
        EMAILS="$(echo "$DETECTED" | jq -c '[.maintainers[].email]')"
        MAINT_FILE="${ROOT_DIR}/MAINTAINERS.json"
        if [[ -f "$MAINT_FILE" ]]; then
            jq --arg repo "$REPO_NAME" --argjson emails "$EMAILS" \
               '.repo_maintainers[$repo] = $emails' "$MAINT_FILE" > "${MAINT_FILE}.tmp" \
               && mv "${MAINT_FILE}.tmp" "$MAINT_FILE"
            echo "Auto-detected maintainers for ${REPO_NAME}: $(echo "$EMAILS" | jq -r 'join(", ")')"
        fi
    fi
fi

echo "Repo '${REPO_NAME}' registered."

if type agent_task_end &>/dev/null; then
    agent_task_end "Register repo: ${REPO_NAME}" "success"
fi
