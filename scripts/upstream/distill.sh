#!/bin/bash
set -euo pipefail

# Distill Engine — Extract governance changes from a live root repo instance
# and prepare them for upstream contribution to root-archetype.
# Run from inside a live root repo instance.

usage() {
    echo "Usage: $0 [file ...] [--dry-run] [--staging-dir DIR]"
    echo ""
    echo "  file ...        Specific files to upstream (default: diff all portable paths)"
    echo "  --dry-run       Show what would be extracted without staging"
    echo "  --staging-dir   Custom staging directory (default: /tmp/archetype-upstream-<ts>)"
    echo ""
    echo "Requires .archetype-manifest.json in the current directory."
    echo "Run scripts/upstream/retroactive-manifest.sh to create one."
    exit 1
}

DRY_RUN=false
STAGING_DIR=""
SPECIFIC_FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --staging-dir)
            STAGING_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            SPECIFIC_FILES+=("$1")
            shift
            ;;
    esac
done

INSTANCE_ROOT="$(pwd)"

# --- Load manifest ---
if [[ ! -f ".archetype-manifest.json" ]]; then
    echo "ERROR: No .archetype-manifest.json found."
    echo "Run scripts/upstream/retroactive-manifest.sh first, or use an instance created with the latest init-project.sh."
    exit 1
fi

# Parse manifest with portable tools (no jq dependency)
ARCHETYPE_PATH=$(python3 -c "import json,sys; print(json.load(open('.archetype-manifest.json'))['archetype_origin'])")
PROJECT_NAME=$(python3 -c "import json,sys; print(json.load(open('.archetype-manifest.json'))['template_values']['PROJECT_NAME'])")
PROJECT_ROOT=$(python3 -c "import json,sys; print(json.load(open('.archetype-manifest.json'))['template_values']['PROJECT_ROOT'])")

if [[ ! -d "$ARCHETYPE_PATH" ]]; then
    echo "ERROR: Archetype path not found: $ARCHETYPE_PATH"
    echo "Update archetype_origin in .archetype-manifest.json"
    exit 1
fi

echo "=== Distill Engine ==="
echo "Instance:  ${INSTANCE_ROOT}"
echo "Project:   ${PROJECT_NAME}"
echo "Archetype: ${ARCHETYPE_PATH}"
echo ""

# --- Setup staging ---
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [[ -z "$STAGING_DIR" ]]; then
    STAGING_DIR="/tmp/archetype-upstream-${TIMESTAMP}"
fi
mkdir -p "$STAGING_DIR"

# --- Core functions ---

reverse_template() {
    local file="$1"
    local output="$2"
    sed -e "s|${PROJECT_NAME}|{{PROJECT_NAME}}|g" \
        -e "s|${PROJECT_ROOT}|{{PROJECT_ROOT}}|g" \
        "$file" > "$output"
}

check_contamination() {
    local file="$1"
    local errors=0

    # After reverse-templating, no project-specific strings should remain
    if grep -qiE "(${PROJECT_NAME})" "$file" 2>/dev/null; then
        echo "  CONTAMINATED: still contains project name '${PROJECT_NAME}'"
        errors=$((errors + 1))
    fi

    if grep -qF "${PROJECT_ROOT}" "$file" 2>/dev/null; then
        echo "  CONTAMINATED: still contains project root '${PROJECT_ROOT}'"
        errors=$((errors + 1))
    fi

    return $errors
}

is_templated_file() {
    local file="$1"
    local templated
    templated=$(python3 -c "
import json
m = json.load(open('.archetype-manifest.json'))
for t in m.get('templated_files', []):
    print(t)
")
    echo "$templated" | grep -qxF "$file"
}

# --- Collect files to process ---
collect_portable_files() {
    local paths
    paths=$(python3 -c "
import json
m = json.load(open('.archetype-manifest.json'))
for p in m.get('portable_paths', []):
    print(p)
")
    local files=()
    while IFS= read -r pattern; do
        if [[ "$pattern" == */ ]]; then
            # Directory pattern — find all files
            if [[ -d "$pattern" ]]; then
                while IFS= read -r f; do
                    files+=("$f")
                done < <(find "$pattern" -type f 2>/dev/null)
            fi
        else
            # Glob pattern
            for f in $pattern; do
                [[ -f "$f" ]] && files+=("$f")
            done
        fi
    done <<< "$paths"
    printf '%s\n' "${files[@]}"
}

if [[ ${#SPECIFIC_FILES[@]} -gt 0 ]]; then
    FILES_TO_PROCESS=("${SPECIFIC_FILES[@]}")
else
    mapfile -t FILES_TO_PROCESS < <(collect_portable_files)
fi

echo "Files to evaluate: ${#FILES_TO_PROCESS[@]}"
echo ""

# --- Process each file ---
CHANGED_FILES=()
NEW_FILES=()
CONTAMINATED_FILES=()
CLEAN_FILES=()

for file in "${FILES_TO_PROCESS[@]}"; do
    [[ -f "$file" ]] || continue

    archetype_file="${ARCHETYPE_PATH}/${file}"
    staged_file="${STAGING_DIR}/${file}"

    # Determine if this is a templated file that needs reverse-templating
    needs_reverse=false
    if is_templated_file "$file"; then
        needs_reverse=true
    fi

    # Create staged version
    mkdir -p "$(dirname "$staged_file")"
    if $needs_reverse; then
        reverse_template "$file" "$staged_file"
    else
        cp "$file" "$staged_file"
    fi

    # Check contamination
    if ! check_contamination "$staged_file"; then
        CONTAMINATED_FILES+=("$file")
        rm "$staged_file"
        continue
    fi

    # Compare with archetype
    if [[ ! -f "$archetype_file" ]]; then
        echo "[NEW]     $file"
        NEW_FILES+=("$file")
        CLEAN_FILES+=("$file")
    elif ! diff -q "$staged_file" "$archetype_file" &>/dev/null; then
        echo "[CHANGED] $file"
        CHANGED_FILES+=("$file")
        CLEAN_FILES+=("$file")
        if ! $DRY_RUN; then
            # Store diff for handoff
            diff -u "$archetype_file" "$staged_file" > "${staged_file}.diff" 2>/dev/null || true
        fi
    else
        # Identical — remove from staging
        rm "$staged_file"
    fi
done

echo ""
echo "=== Summary ==="
echo "Changed: ${#CHANGED_FILES[@]}"
echo "New:     ${#NEW_FILES[@]}"
echo "Contaminated (blocked): ${#CONTAMINATED_FILES[@]}"

if [[ ${#CONTAMINATED_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "Contaminated files need manual cleanup before upstreaming:"
    for f in "${CONTAMINATED_FILES[@]}"; do
        echo "  - $f"
    done
fi

if [[ ${#CLEAN_FILES[@]} -eq 0 ]]; then
    echo ""
    echo "Nothing to upstream — all portable files match the archetype."
    rm -rf "$STAGING_DIR"
    exit 0
fi

if $DRY_RUN; then
    echo ""
    echo "Dry run — no files staged."
    rm -rf "$STAGING_DIR"
    exit 0
fi

# --- Generate handoff document ---
HANDOFF_FILE="${STAGING_DIR}/upstream-handoff.md"
cat > "$HANDOFF_FILE" << HEOF
# Upstream Contribution: ${PROJECT_NAME} → root-archetype

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Source Instance:** ${INSTANCE_ROOT}
**Files Proposed:** ${#CLEAN_FILES[@]}

## Changed Files

HEOF

for file in "${CHANGED_FILES[@]}"; do
    staged_file="${STAGING_DIR}/${file}"
    cat >> "$HANDOFF_FILE" << FEOF
### \`${file}\`

**Type:** Modified (exists in archetype)

<details>
<summary>Diff</summary>

\`\`\`diff
$(cat "${staged_file}.diff" 2>/dev/null || echo "no diff available")
\`\`\`

</details>

FEOF
done

for file in "${NEW_FILES[@]}"; do
    cat >> "$HANDOFF_FILE" << FEOF
### \`${file}\`

**Type:** New file (not in archetype)

FEOF
done

cat >> "$HANDOFF_FILE" << HEOF

## Considerations

- All files have passed reverse-template sanitization
- No project-specific references remain in staged files
- Maintainer should verify these changes are project-agnostic before merging

## Review Checklist

- [ ] Each file is project-agnostic (no instance-specific logic)
- [ ] Changes are useful for all future instances
- [ ] No regressions to existing archetype functionality
- [ ] Validators pass after applying changes
HEOF

echo ""
echo "=== Staging complete ==="
echo "Staged at: ${STAGING_DIR}"
echo "Handoff:   ${HANDOFF_FILE}"
echo ""
echo "Next: run scripts/upstream/submit-pr.sh --staging-dir ${STAGING_DIR}"
