#!/bin/bash
set -euo pipefail

# Detect maintainers from a child repo using multiple heuristics
# Usage: detect-maintainers.sh <repo-name> <repo-path>
# Output: JSON to stdout

usage() {
    echo "Usage: $0 <repo-name> <repo-path>"
    exit 1
}

[[ $# -lt 2 ]] && usage

REPO_NAME="$1"
REPO_PATH="$2"

[[ -d "$REPO_PATH" ]] || { echo "{}"; exit 0; }

MAINTAINERS=()

# Helper: add maintainer if not already present
add_maintainer() {
    local email="$1" source="$2"
    [[ -z "$email" ]] && return
    # Normalize: lowercase, trim
    email="$(echo "$email" | tr '[:upper:]' '[:lower:]' | xargs)"
    # Skip noreply / bot addresses
    [[ "$email" == *noreply* || "$email" == *bot@* || "$email" == *[bot]* ]] && return
    # Check for duplicate
    for existing in "${MAINTAINERS[@]+"${MAINTAINERS[@]}"}"; do
        [[ "$existing" == "${email}|"* ]] && return
    done
    MAINTAINERS+=("${email}|${source}")
}

# --- 1. MAINTAINERS.json ---
if [[ -f "${REPO_PATH}/MAINTAINERS.json" ]]; then
    if command -v jq &>/dev/null; then
        while IFS= read -r email; do
            add_maintainer "$email" "MAINTAINERS.json"
        done < <(jq -r '.global_maintainers[]? // empty, (.repo_maintainers[]?[]? // empty)' "${REPO_PATH}/MAINTAINERS.json" 2>/dev/null || true)
    fi
elif [[ -f "${REPO_PATH}/MAINTAINERS" ]]; then
    while IFS= read -r line; do
        email="$(echo "$line" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || true)"
        add_maintainer "$email" "MAINTAINERS"
    done < "${REPO_PATH}/MAINTAINERS"
fi

# --- 2. CODEOWNERS ---
if [[ -f "${REPO_PATH}/CODEOWNERS" ]] || [[ -f "${REPO_PATH}/.github/CODEOWNERS" ]]; then
    CODEOWNERS_FILE="${REPO_PATH}/CODEOWNERS"
    [[ -f "$CODEOWNERS_FILE" ]] || CODEOWNERS_FILE="${REPO_PATH}/.github/CODEOWNERS"
    while IFS= read -r line; do
        # Extract emails from CODEOWNERS lines (skip comments)
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        for token in $line; do
            if [[ "$token" == *@*.* ]] && [[ "$token" != @* || "$token" == *@*.* ]]; then
                email="$(echo "$token" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || true)"
                add_maintainer "$email" "CODEOWNERS"
            fi
        done
    done < "$CODEOWNERS_FILE"
fi

# --- 3. package.json ---
if [[ -f "${REPO_PATH}/package.json" ]] && command -v jq &>/dev/null; then
    # Author field (string or object)
    author_email="$(jq -r '.author | if type == "object" then .email // empty elif type == "string" then (capture("<?(?<e>[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})>?") | .e) // empty else empty end' "${REPO_PATH}/package.json" 2>/dev/null || true)"
    add_maintainer "$author_email" "package.json"
    # Contributors
    while IFS= read -r email; do
        add_maintainer "$email" "package.json"
    done < <(jq -r '.contributors[]? | if type == "object" then .email // empty elif type == "string" then (capture("<?(?<e>[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})>?") | .e) // empty else empty end' "${REPO_PATH}/package.json" 2>/dev/null || true)
fi

# --- 4. Cargo.toml ---
if [[ -f "${REPO_PATH}/Cargo.toml" ]]; then
    while IFS= read -r line; do
        email="$(echo "$line" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || true)"
        add_maintainer "$email" "Cargo.toml"
    done < <(grep -i 'authors' "${REPO_PATH}/Cargo.toml" 2>/dev/null || true)
fi

# --- 5. pyproject.toml ---
if [[ -f "${REPO_PATH}/pyproject.toml" ]]; then
    while IFS= read -r line; do
        email="$(echo "$line" | grep -oP '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' || true)"
        add_maintainer "$email" "pyproject.toml"
    done < <(grep -iA5 'authors' "${REPO_PATH}/pyproject.toml" 2>/dev/null || true)
fi

# --- 6. Git log (top 3 committers) ---
if [[ -d "${REPO_PATH}/.git" ]]; then
    while IFS= read -r email; do
        add_maintainer "$email" "git_log"
    done < <(git -C "$REPO_PATH" log --format='%ae' 2>/dev/null | sort | uniq -c | sort -rn | head -3 | awk '{print $2}' || true)
fi

# --- Build JSON output ---
if [[ ${#MAINTAINERS[@]} -eq 0 ]]; then
    echo "{}"
    exit 0
fi

# Build JSON manually (no jq dependency for output)
echo -n "{\"repo\":\"${REPO_NAME}\",\"maintainers\":["
first=true
for entry in "${MAINTAINERS[@]}"; do
    IFS='|' read -r email source <<< "$entry"
    if [[ "$first" == true ]]; then
        first=false
    else
        echo -n ","
    fi
    echo -n "{\"email\":\"${email}\",\"source\":\"${source}\"}"
done
echo "]}"
