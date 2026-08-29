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
# Resolve the default here rather than inside the heredoc. Note the wording
# avoids an apostrophe on purpose: a single quote inside a ${VAR:-default}
# expansion is treated as a quoting character even within double quotes, so the
# old default ("this repo's purpose") left an unterminated quote — the heredoc
# died at runtime with "bad substitution" and aborted registration.
PURPOSE_TEXT="${PURPOSE:-Configure the purpose of this repo.}"

if [[ "$NO_SCAFFOLD" != true ]] && [[ -d "$REPO_PATH" ]]; then
    if [[ ! -f "${REPO_PATH}/CLAUDE.md" ]]; then
        cat > "${REPO_PATH}/CLAUDE.md" << CLAUDE_EOF
# ${REPO_NAME}

## Purpose

${PURPOSE_TEXT}

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

# --- Record in repos/repos.json ---
# repos/ contents are gitignored, so a clone of this root has no child repos.
# This manifest is the only record of how to get them back; scripts/bootstrap.sh
# reads it to re-clone them. A repo with no git remote is recorded without a
# clone_url and is skipped by bootstrap (local-only or symlinked).
REPOS_MANIFEST="${REPOS_DIR}/repos.json"
if command -v jq &>/dev/null; then
    CLONE_URL=""
    if [[ -d "${REPO_PATH}/.git" ]]; then
        CLONE_URL="$(git -C "$REPO_PATH" remote get-url origin 2>/dev/null || echo "")"
    fi

    [[ -f "$REPOS_MANIFEST" ]] || echo '{"repos": []}' > "$REPOS_MANIFEST"

    if jq --arg name "$REPO_NAME" \
          --arg url "$CLONE_URL" \
          --arg purpose "$PURPOSE" \
          '.repos = ((.repos // []) | map(select(.name != $name)) + [{name: $name, clone_url: $url, purpose: $purpose}] | sort_by(.name))' \
          "$REPOS_MANIFEST" > "${REPOS_MANIFEST}.tmp" 2>/dev/null; then
        mv "${REPOS_MANIFEST}.tmp" "$REPOS_MANIFEST"
        if [[ -n "$CLONE_URL" ]]; then
            echo "Recorded in repos/repos.json (clone_url: ${CLONE_URL})"
        else
            echo "Recorded in repos/repos.json (no git remote — bootstrap will skip cloning it)"
        fi
    else
        rm -f "${REPOS_MANIFEST}.tmp"
        echo "WARNING: could not update repos/repos.json" >&2
    fi
else
    echo "WARNING: jq not found — repos/repos.json not updated (bootstrap.sh cannot re-clone this repo)" >&2
fi

echo "Repo '${REPO_NAME}' registered."

if type agent_task_end &>/dev/null; then
    agent_task_end "Register repo: ${REPO_NAME}" "success"
fi
