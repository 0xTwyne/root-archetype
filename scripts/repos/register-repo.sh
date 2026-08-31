#!/bin/bash
set -euo pipefail

# Register a child repo with the root governance repo
# Usage: register-repo.sh <name> <path> [--purpose "description"]


# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

usage() {
    echo "Usage: $0 <name> <path> [--purpose \"description\"] [--no-scaffold]"
    echo ""
    echo "  name           Short identifier for the repo"
    echo "  path           Absolute path to the repo"
    echo "  --purpose      Optional description of the repo's role"
    echo "  --no-scaffold  Skip agent file seeding (for infrastructure repos)"
    echo "  --maintainer   Email of a maintainer for THIS repo. Repeatable."
    echo "                 Recorded in MAINTAINERS.json -> repo_maintainers[<name>],"
    echo "                 which pre-edit-guard.sh reads to decide who may edit"
    echo "                 the repo's config. Declaring it beats the detection"
    echo "                 fallback, which guesses from committer history and"
    echo "                 packaging metadata and is wrong for any repo that"
    echo "                 arrives as a squashed import authored by whoever ran"
    echo "                 the import."
    exit 1
}

[[ $# -lt 2 ]] && usage

REPO_NAME="$1"
REPO_PATH="$2"
shift 2

PURPOSE=""
NO_SCAFFOLD=false
DECLARED_MAINTAINERS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --purpose) PURPOSE="$2"; shift 2 ;;
        --no-scaffold) NO_SCAFFOLD=true; shift ;;
        --maintainer) DECLARED_MAINTAINERS+=("$2"); shift 2 ;;
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

# --- Seed the child's CLAUDE.md ---------------------------------------------
#
# This runs even under --no-scaffold. The pointer below is not agent
# scaffolding, it is a safety notice, and the repo most in need of it is the
# knowledge repo -- which init-project.sh registers with --no-scaffold.
#
# Why it is needed: Claude Code resolves skills from a project's own
# .claude/skills/, and a child repo has none, so a session LAUNCHED inside one
# gets no /wrap-up, no /safe-commit, and no session hooks -- no audit trail and
# no progress report. The failure is silent. CLAUDE.md is the one channel that
# still reaches such a session, because it loads from the working directory and
# every directory above it.
if [[ -d "$REPO_PATH" ]] && [[ ! -f "${REPO_PATH}/CLAUDE.md" ]]; then
    {
        echo "# ${REPO_NAME}"
        echo ""
        if [[ "$NO_SCAFFOLD" != true ]]; then
            echo "## Purpose"
            echo ""
            echo "${PURPOSE_TEXT}"
            echo ""
            echo "## Code Style"
            echo ""
            echo "- Follow existing project conventions"
            echo "- Run validation after producing artifacts"
            echo ""
        fi
        echo "## Session tooling lives in the governance root"
        echo ""
        echo "Skills resolve from a project's own \`.claude/skills/\`, and this repo has"
        echo "none. A session **launched here** therefore has no \`/wrap-up\`,"
        echo "\`/safe-commit\` or \`/project-wiki\`, and none of the session hooks: no"
        echo "audit trail, no progress report, no session branch. Nothing announces this."
        echo ""
        echo "**Start sessions from the governance root and \`cd\` here.\`\`"
        echo "CLAUDE_PROJECT_DIR\` stays at the root, the tooling resolves, and this repo"
        echo "is still fully editable. Starting at the root and moving here works;"
        echo "launching here does not."
        echo ""
        echo "If you are already in a session launched here: finish the work, then run"
        echo "\`/wrap-up\` from a root session so it gets recorded."
    } > "${REPO_PATH}/CLAUDE.md"
    echo "Seeded: ${REPO_PATH}/CLAUDE.md"
fi

# A repo that already carries AGENT.md or CLAUDE.md is configured, and very
# often is not ours to write into: registering a collaborator's existing repo
# dropped a generic agents/developer.md into their working tree, where it shows
# up as an untracked file in a clone the registering user does not own.
# --no-scaffold covers the case you anticipate; this covers the one you do not.
ALREADY_CONFIGURED=false
if [[ -f "${REPO_PATH}/AGENT.md" || -f "${REPO_PATH}/CLAUDE.md" ]]; then
    ALREADY_CONFIGURED=true
fi

if [[ "$NO_SCAFFOLD" != true ]] && [[ -d "$REPO_PATH" ]] && [[ "$ALREADY_CONFIGURED" == "true" ]]; then
    echo "Skipped seeding: ${REPO_NAME} already has agent instructions."
elif [[ "$NO_SCAFFOLD" != true ]] && [[ -d "$REPO_PATH" ]]; then

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

# --- Record the repo maintainers ---
# repo_maintainers[<name>] is what pre-edit-guard.sh reads to decide who may
# edit this repo's config, so this is a permission decision, not bookkeeping.
# An explicit --maintainer wins; detection stays as a fallback and is labelled
# as such, because for a repo imported as one squashed commit it names whoever
# ran the import rather than whoever owns the work.
MAINT_FILE="${ROOT_DIR}/MAINTAINERS.json"
if command -v jq &>/dev/null && [[ -f "$MAINT_FILE" ]]; then
    MAINT_SOURCE=""
    EMAILS_JSON=""
    if (( ${#DECLARED_MAINTAINERS[@]} > 0 )); then
        EMAILS_JSON="$(printf '%s\n' "${DECLARED_MAINTAINERS[@]}" | jq -R . | jq -sc 'unique')"
        MAINT_SOURCE="declared"
    else
        DETECT_SCRIPT="${ROOT_DIR}/scripts/utils/detect-maintainers.sh"
        if [[ -f "$DETECT_SCRIPT" && -d "$REPO_PATH" ]]; then
            DETECTED="$(bash "$DETECT_SCRIPT" "$REPO_NAME" "$REPO_PATH" 2>/dev/null || echo "")"
            if [[ -n "$DETECTED" && "$DETECTED" != "{}" ]]; then
                EMAILS_JSON="$(echo "$DETECTED" | jq -c '[.maintainers[].email] | unique')"
                MAINT_SOURCE="auto-detected"
            fi
        fi
    fi

    if [[ -n "$EMAILS_JSON" && "$EMAILS_JSON" != "[]" ]]; then
        if jq --arg repo "$REPO_NAME" --argjson emails "$EMAILS_JSON" \
              '.repo_maintainers = ((.repo_maintainers // {}) | .[$repo] = $emails)' \
              "$MAINT_FILE" > "${MAINT_FILE}.tmp" 2>/dev/null; then
            mv "${MAINT_FILE}.tmp" "$MAINT_FILE"
            echo "Maintainers for ${REPO_NAME} (${MAINT_SOURCE}): $(echo "$EMAILS_JSON" | jq -r 'join(", ")')"
            # Spelt as `if`, not `[[ ]] &&`: a trailing false AND-list under
            # `set -e` is a repeat trap in this codebase.
            if [[ "$MAINT_SOURCE" == "auto-detected" ]]; then
                echo "  Detected from repo metadata, not declared. Re-run with --maintainer to correct it."
            fi
        else
            rm -f "${MAINT_FILE}.tmp"
            echo "WARNING: could not update MAINTAINERS.json" >&2
        fi
    else
        echo "No maintainer recorded for ${REPO_NAME}. Pass --maintainer <email> to set one."
        echo "  Until then nobody but a global maintainer can edit this repo's config."
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

    # Re-registering without --purpose must not erase the purpose on record.
    # The rewrite below replaces the whole entry, so carry it forward.
    if [[ -z "$PURPOSE" ]]; then
        PURPOSE="$(jq -r --arg name "$REPO_NAME" \
            '(.repos[]? | select(.name == $name) | .purpose) // ""' \
            "$REPOS_MANIFEST" 2>/dev/null || echo "")"
    fi

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
