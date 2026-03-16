#!/bin/bash
set -euo pipefail

# Submit PR — Takes staged files from distill.sh and creates a PR against root-archetype.
# Run from inside a live root repo instance.

usage() {
    echo "Usage: $0 --staging-dir DIR [--no-push]"
    echo ""
    echo "  --staging-dir DIR   Path to staging directory from distill.sh"
    echo "  --no-push           Create branch and commit but don't push or create PR"
    exit 1
}

STAGING_DIR=""
NO_PUSH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staging-dir)
            STAGING_DIR="$2"
            shift 2
            ;;
        --no-push)
            NO_PUSH=true
            shift
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

if [[ -z "$STAGING_DIR" ]]; then
    echo "ERROR: --staging-dir is required"
    usage
fi

if [[ ! -d "$STAGING_DIR" ]]; then
    echo "ERROR: Staging directory not found: $STAGING_DIR"
    exit 1
fi

# --- Load manifest ---
if [[ ! -f ".archetype-manifest.json" ]]; then
    echo "ERROR: No .archetype-manifest.json found in current directory."
    exit 1
fi

ARCHETYPE_PATH=$(python3 -c "import json; print(json.load(open('.archetype-manifest.json'))['archetype_origin'])")
PROJECT_NAME=$(python3 -c "import json; print(json.load(open('.archetype-manifest.json'))['template_values']['PROJECT_NAME'])")

if [[ ! -d "$ARCHETYPE_PATH/.git" ]]; then
    echo "ERROR: Archetype path is not a git repo: $ARCHETYPE_PATH"
    exit 1
fi

HANDOFF_FILE="${STAGING_DIR}/upstream-handoff.md"
if [[ ! -f "$HANDOFF_FILE" ]]; then
    echo "ERROR: No handoff document found. Run distill.sh first."
    exit 1
fi

DATE_STAMP=$(date +%Y-%m-%d)
BRANCH_NAME="upstream/${PROJECT_NAME}/${DATE_STAMP}"

echo "=== Submit Upstream PR ==="
echo "Archetype: ${ARCHETYPE_PATH}"
echo "Branch:    ${BRANCH_NAME}"
echo "Source:    ${STAGING_DIR}"
echo ""

# --- Create branch in archetype ---
cd "$ARCHETYPE_PATH"

# Ensure we're on a clean state
if [[ -n "$(git status --porcelain)" ]]; then
    echo "WARNING: Archetype repo has uncommitted changes."
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")
git checkout "$MAIN_BRANCH" 2>/dev/null || git checkout main
git pull --ff-only 2>/dev/null || true
git checkout -b "$BRANCH_NAME"

# --- Copy staged files into archetype ---
echo "Copying staged files..."
STAGED_COUNT=0
while IFS= read -r file; do
    # Skip handoff and diff files
    [[ "$file" == *.diff ]] && continue
    [[ "$file" == "upstream-handoff.md" ]] && continue

    rel_path="${file#"$STAGING_DIR/"}"
    dest="${ARCHETYPE_PATH}/${rel_path}"
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    echo "  Copied: $rel_path"
    STAGED_COUNT=$((STAGED_COUNT + 1))
done < <(find "$STAGING_DIR" -type f)

# --- Copy handoff to handoffs/active/ ---
HANDOFF_DEST="handoffs/active/upstream-${PROJECT_NAME}-${DATE_STAMP}.md"
mkdir -p "$(dirname "$HANDOFF_DEST")"
cp "$HANDOFF_FILE" "$HANDOFF_DEST"
echo "  Handoff: $HANDOFF_DEST"

# --- Run validators ---
echo ""
echo "Running validators..."
VALIDATORS_PASS=true

if [[ -x "scripts/validate/validate_agents_structure.py" ]]; then
    if python3 scripts/validate/validate_agents_structure.py 2>&1; then
        echo "  Agent structure: PASS"
    else
        echo "  Agent structure: FAIL"
        VALIDATORS_PASS=false
    fi
fi

if [[ -x "scripts/validate/validate_agents_references.py" ]]; then
    if python3 scripts/validate/validate_agents_references.py 2>&1; then
        echo "  Agent references: PASS"
    else
        echo "  Agent references: FAIL"
        VALIDATORS_PASS=false
    fi
fi

if ! $VALIDATORS_PASS; then
    echo ""
    echo "WARNING: Validators failed. Review the output above."
    read -rp "Continue with PR anyway? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborting. Branch ${BRANCH_NAME} has been created — clean up manually."
        exit 1
    fi
fi

# --- Commit ---
git add -A
git commit -m "upstream(${PROJECT_NAME}): contribute governance changes

Source: ${PROJECT_NAME}
Files: ${STAGED_COUNT}
Handoff: ${HANDOFF_DEST}

Co-Authored-By: distill.sh <noreply@root-archetype>"

echo ""
echo "Committed to branch: ${BRANCH_NAME}"

if $NO_PUSH; then
    echo ""
    echo "=== Branch ready (--no-push) ==="
    echo "To push and create PR manually:"
    echo "  cd ${ARCHETYPE_PATH}"
    echo "  git push -u origin ${BRANCH_NAME}"
    echo "  gh pr create --title 'upstream(${PROJECT_NAME}): governance contribution' --body-file ${HANDOFF_DEST}"
    exit 0
fi

# --- Push and create PR ---
echo "Pushing branch..."
git push -u origin "$BRANCH_NAME"

echo "Creating PR..."
PR_BODY=$(cat "$HANDOFF_DEST")
PR_URL=$(gh pr create \
    --title "upstream(${PROJECT_NAME}): governance contribution ${DATE_STAMP}" \
    --body "$PR_BODY" \
    --base "$MAIN_BRANCH" \
    2>&1)

echo ""
echo "=== PR Created ==="
echo "$PR_URL"
echo ""
echo "Return to instance: cd ${STAGING_DIR%/*}"
