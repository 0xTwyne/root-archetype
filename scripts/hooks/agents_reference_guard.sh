#!/bin/bash
set -euo pipefail

# Hook: agents_reference_guard.sh
# Trigger: PreToolUse → Write|Edit
# Purpose: Validate local markdown references in governance files

# Harness sends {tool_name, tool_input:{...}} on stdin; accept the legacy
# flat shape as fallback. Unparseable input fails open, but with a stderr
# diagnostic instead of silently.
INPUT="$(cat)"
if ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    echo "agents_reference_guard: could not parse hook input as JSON — allowing" >&2
    exit 0
fi
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .file_path // empty')"

if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Only check governance files
GOVERNANCE_PATTERNS=(
    "agents/"
    "docs/guides/"
    "docs/reference/"
    "CLAUDE.md"
    "CLAUDE_GUIDE.md"
    "README.md"
)

IS_GOVERNANCE=false
for pattern in "${GOVERNANCE_PATTERNS[@]}"; do
    if [[ "$FILE_PATH" == *"$pattern"* ]]; then
        IS_GOVERNANCE=true
        break
    fi
done

if [[ "$IS_GOVERNANCE" != "true" ]]; then
    exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Extract local markdown references and check existence
FILE_DIR=$(dirname "$FILE_PATH")
MISSING=()

# Find backtick references like `path/file.md`
while IFS= read -r ref; do
    # Skip URLs, anchors, and non-path references
    [[ "$ref" =~ ^https?:// ]] && continue
    [[ "$ref" =~ ^# ]] && continue
    [[ ! "$ref" =~ \. ]] && continue

    # Resolve relative path
    RESOLVED="${FILE_DIR}/${ref}"
    if [[ ! -f "$RESOLVED" && ! -d "$RESOLVED" ]]; then
        # Try from repo root
        REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
        if [[ -n "$REPO_ROOT" && ! -f "${REPO_ROOT}/${ref}" && ! -d "${REPO_ROOT}/${ref}" ]]; then
            MISSING+=("$ref")
        fi
    fi
done < <(rg -o '`([^`]+\.(md|sh|py|json|yaml|yml))`' --replace '$1' "$FILE_PATH" 2>/dev/null || true)

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "WARNING: Found references to non-existent files in ${FILE_PATH}:"
    for m in "${MISSING[@]}"; do
        echo "  - $m"
    done
    # Warning only — don't block
    exit 0
fi

exit 0
