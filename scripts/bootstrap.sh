#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a fresh clone of a governance root into a working state.
#
# init-project.sh generates the engine adapter files (CLAUDE.md / CODEX.md,
# .claude/settings.json, .claude/skills/, .claude/commands/) at project
# creation, but those files are gitignored — so anyone who later CLONES the
# project gets none of them. Without them no hooks fire and no skills or
# commands exist. The child repos under repos/ are gitignored too.
#
# This script restores all of it. Run it once after cloning; safe to re-run.
#
# Note: regeneration overwrites the engine doc and .claude/settings.json from
# the templates in agents/engines/. Put local customisation in
# .claude/settings.local.json, which is never touched.
#
# Usage:
#   bash scripts/bootstrap.sh [--engine claude|codex] [--skip-clone]

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST="$ROOT_DIR/.archetype-manifest.json"
REPOS_MANIFEST="$ROOT_DIR/repos/repos.json"

# Read a value from the archetype manifest, with a fallback so the script still
# works when the manifest or jq is missing.
manifest_value() {
    local jq_path="$1" fallback="$2" value=""
    if [[ -f "$MANIFEST" ]] && command -v jq >/dev/null 2>&1; then
        value="$(jq -r "$jq_path // empty" "$MANIFEST" 2>/dev/null || echo "")"
    fi
    echo "${value:-$fallback}"
}

# Default to the engine this project was initialised with.
ENGINE="$(manifest_value '.engine' 'claude')"
SKIP_CLONE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine)     ENGINE="${2:-}"; shift 2 ;;
        --skip-clone) SKIP_CLONE=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--engine claude|codex] [--skip-clone]"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Portable warning accumulator. An empty array expanded under `set -u` errors on
# bash < 4.4 (macOS ships 3.2), so track the count separately and guard the
# expansion when printing.
WARNINGS=()
WARN_COUNT=0
warn() { WARNINGS+=("$1"); WARN_COUNT=$((WARN_COUNT + 1)); }

echo "=== $(basename "$ROOT_DIR") bootstrap ==="
echo "Root:   $ROOT_DIR"
echo "Engine: $ENGINE"
echo ""

# --- 1. Engine adapter files ---
echo "--- 1/4 Engine adapters ---"
bash "$ROOT_DIR/scripts/utils/generate-engine.sh" --engine "$ENGINE" --project-dir "$ROOT_DIR"
echo ""

# --- 2. Child repo clones ---
# Child repos live under repos/ and are gitignored, so a clone of the root has
# none of them. repos/repos.json records how to get them back; it is maintained
# by scripts/repos/register-repo.sh.
echo "--- 2/4 Child repos ---"
if [[ "$SKIP_CLONE" == "true" ]]; then
    echo "  Skipped (--skip-clone)."
elif [[ ! -f "$REPOS_MANIFEST" ]]; then
    echo "  No repos/repos.json — nothing to clone."
    echo "  (Child repos registered with register-repo.sh are recorded there.)"
elif ! command -v jq >/dev/null 2>&1; then
    echo "  jq not installed — cannot read repos/repos.json."
    warn "Install jq, then re-run to clone the child repos listed in repos/repos.json"
else
    # Any repo entry without a clone_url is local-only (e.g. a symlink to a
    # path on this machine, or data synced from elsewhere) and is skipped.
    # Read with a while-loop rather than `mapfile`, which is bash 4+ only.
    REPO_LINES=()
    REPO_COUNT=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        REPO_LINES+=("$line")
        REPO_COUNT=$((REPO_COUNT + 1))
    done < <(jq -r '.repos[]? | select(.clone_url != null and .clone_url != "") | "\(.name)\t\(.clone_url)"' "$REPOS_MANIFEST" 2>/dev/null || true)

    if [[ "$REPO_COUNT" -eq 0 ]]; then
        echo "  No cloneable repos listed in repos/repos.json."
    else
        if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
            warn "gh is installed but not authenticated — run 'gh auth login' before cloning private child repos"
        fi

        mkdir -p "$ROOT_DIR/repos"
        for line in ${REPO_LINES[@]+"${REPO_LINES[@]}"}; do
            name="${line%%$'\t'*}"
            url="${line#*$'\t'}"
            dest="$ROOT_DIR/repos/$name"

            if [[ -d "$dest/.git" ]]; then
                echo "  $name: already cloned"
                continue
            fi
            if [[ -d "$dest" ]] && [[ -n "$(ls -A "$dest" 2>/dev/null)" ]]; then
                echo "  $name: directory exists but is not a git repo — leaving it alone"
                warn "repos/$name exists but is not a git clone; resolve by hand"
                continue
            fi

            echo "  $name: cloning..."
            # GIT_TERMINAL_PROMPT=0 makes a missing credential fail fast rather
            # than blocking on an interactive prompt. For GitHub URLs prefer
            # `gh repo clone`, which authenticates through gh and therefore
            # works even when git has no credential helper configured.
            clone_err=""
            if [[ "$url" == *github.com* ]] && command -v gh >/dev/null 2>&1; then
                clone_err="$(GIT_TERMINAL_PROMPT=0 gh repo clone "$url" "$dest" -- --quiet 2>&1)" || clone_err="${clone_err:-clone failed}"
            else
                clone_err="$(GIT_TERMINAL_PROMPT=0 git clone --quiet "$url" "$dest" 2>&1)" || clone_err="${clone_err:-clone failed}"
            fi

            if [[ -d "$dest/.git" ]]; then
                echo "  $name: ok"
            else
                echo "  $name: CLONE FAILED"
                [[ -n "$clone_err" ]] && echo "$clone_err" | sed 's/^/    /'
                warn "Could not clone $name from $url — check access and authentication"
            fi
        done
    fi
fi
echo ""

# --- 3. Agent registry / repo sync ---
echo "--- 3/4 Agent registry ---"
sync_out=""
if sync_out="$(bash "$ROOT_DIR/scripts/repos/sync-repos.sh" 2>&1)"; then
    echo "  Registry rebuilt."
else
    echo "  Registry rebuild reported errors:"
    echo "$sync_out" | tail -5 | sed 's/^/    /'
    warn "scripts/repos/sync-repos.sh failed — run it directly to see why"
fi
echo ""

# --- 4. Verify ---
echo "--- 4/4 Verification ---"
check_path() {
    local label="$1" path="$2"
    if [[ -e "$ROOT_DIR/$path" ]]; then
        echo "  ok    $label"
    else
        echo "  MISS  $label ($path)"
        warn "Missing after bootstrap: $path"
    fi
}

check_nonempty_dir() {
    local label="$1" path="$2" count
    count="$(find "$ROOT_DIR/$path" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$count" -gt 0 ]]; then
        echo "  ok    $label ($count)"
    else
        echo "  MISS  $label — $path is empty"
        warn "$path was generated but is empty"
    fi
}

check_path "agent instructions" "AGENT.md"

case "$ENGINE" in
    claude)
        check_path         "engine doc"     "CLAUDE.md"
        check_path         "hook settings"  ".claude/settings.json"
        check_nonempty_dir "skill wrappers" ".claude/skills"
        check_nonempty_dir "commands"       ".claude/commands"
        ;;
    codex)
        check_path "engine doc" "CODEX.md"
        ;;
esac

echo ""
if [[ "$WARN_COUNT" -gt 0 ]]; then
    echo "=== Bootstrap finished with $WARN_COUNT warning(s) ==="
    for w in ${WARNINGS[@]+"${WARNINGS[@]}"}; do
        echo "  - $w"
    done
    echo ""
    echo "Fix the above, then re-run: bash scripts/bootstrap.sh"
    exit 1
fi

echo "=== Bootstrap complete ==="
echo ""
echo "Next steps:"
echo "  1. RESTART your agent session so the generated $ENGINE config loads."
echo "  2. Read AGENT.md."
