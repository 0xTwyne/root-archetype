#!/bin/bash
set -euo pipefail

# Register a person's aliases in the knowledge repo's identities.json, and reconcile
# any per-user directories already created under one of those aliases.
#
# Run this once per person, on their first session. It is idempotent.
#
# Why: session-start resolves the user from `gh api user --jq .login`, falling
# back to `git config user.name`, then $USER — sanitised to [a-zA-Z0-9_-]. The
# same person gets a different directory depending on which fallback fired, so
# their history splits and per-user isolation stops meaning anything. Nothing
# errors when that happens, which is why it needs a deliberate step.
#
# Usage:
#   register-identity.sh [--canonical <name>] [--alias <name>]... [--apply] [--dry-run]
#
#   --canonical  Directory name to consolidate under. Defaults to the gh login,
#                which is the only identity stable across machines and the one
#                repo permissions are granted to.
#   --alias      Extra alias to record. Repeatable. Detected identities (gh
#                login, git user.name raw and sanitised, git user.email, $USER)
#                are always included.
#   --apply      Actually move stray directories. Without it, this only reports.
#   --dry-run    Alias for the default reporting behaviour.


# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
CANONICAL=""
EXTRA_ALIASES=()
APPLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --canonical) CANONICAL="${2:-}"; shift 2 ;;
        --alias)     EXTRA_ALIASES+=("${2:-}"); shift 2 ;;
        --apply)     APPLY=true; shift ;;
        --dry-run)   APPLY=false; shift ;;
        -h|--help)   sed -n '5,26p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 1; }

# --- Resolve the knowledge repo the way the hooks do ---
LOG_NAME=""
if [[ -f "$ROOT_DIR/.archetype-manifest.json" ]]; then
    LOG_NAME="$(jq -r '.log_repo_name // empty' "$ROOT_DIR/.archetype-manifest.json" 2>/dev/null || echo "")"
fi
[[ -n "$LOG_NAME" ]] || { echo "ERROR: no log_repo_name in .archetype-manifest.json" >&2; exit 1; }
LOG_REPO="$ROOT_DIR/repos/$LOG_NAME"
[[ -d "$LOG_REPO/.git" ]] || {
    echo "ERROR: knowledge repo not found at $LOG_REPO" >&2
    echo "  Run: bash scripts/bootstrap.sh" >&2
    exit 1
}

REGISTRY="$LOG_REPO/identities.json"
if [[ ! -f "$REGISTRY" ]]; then
    echo '{"users": []}' > "$REGISTRY"
    echo "Created $REGISTRY"
fi

# --- Collect every identity this machine could present ---
GH_LOGIN="$(gh api user --jq '.login' 2>/dev/null || echo "")"
GIT_NAME="$(git config user.name 2>/dev/null || echo "")"
GIT_EMAIL="$(git config user.email 2>/dev/null || echo "")"
GIT_NAME_SANITIZED="$(printf '%s' "$GIT_NAME" | tr -cd 'a-zA-Z0-9_-')"
SHELL_USER="${USER:-}"

[[ -n "$CANONICAL" ]] || CANONICAL="$GH_LOGIN"
if [[ -z "$CANONICAL" ]]; then
    echo "ERROR: could not determine a canonical name." >&2
    echo "  gh is not authenticated, so pass one explicitly:" >&2
    echo "    bash scripts/utils/register-identity.sh --canonical <your-github-login>" >&2
    echo "  Do not guess — the canonical name decides which directory your work lands in." >&2
    exit 1
fi

# Usernames that identify a container image rather than a person. $USER is
# "node" in every devcontainer built from the same image, "root" in a bare
# container, "ubuntu"/"ec2-user" on a stock cloud VM. Recording one as an alias
# maps EVERY unregistered person on that image onto whoever registered first —
# the exact identity collision this registry exists to prevent, inverted.
# An explicit --alias still wins, on the assumption it was deliberate.
_is_generic_username() {
    case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        node|root|ubuntu|vscode|user|dev|admin|devcontainer|codespace|ec2-user|runner)
            return 0 ;;
        *) return 1 ;;
    esac
}

ALIASES=()
for a in "$GH_LOGIN" "$GIT_NAME" "$GIT_NAME_SANITIZED" "$GIT_EMAIL" "$SHELL_USER"; do
    [[ -n "$a" && "$a" != "$CANONICAL" ]] || continue
    if _is_generic_username "$a"; then
        echo "  skipped:   $a (generic container username, not a person)" >&2
        continue
    fi
    ALIASES+=("$a")
done
for a in ${EXTRA_ALIASES[@]+"${EXTRA_ALIASES[@]}"}; do
    [[ -n "$a" && "$a" != "$CANONICAL" ]] || continue
    ALIASES+=("$a")
done

echo "=== Identity registration ==="
echo "  canonical: $CANONICAL"
if [[ ${#ALIASES[@]} -gt 0 ]]; then
    printf '  alias:     %s\n' "${ALIASES[@]}"
else
    echo "  alias:     (none beyond the canonical name)"
fi
echo ""

# --- Merge into the registry ---
ALIAS_JSON="$(printf '%s\n' ${ALIASES[@]+"${ALIASES[@]}"} | jq -R . | jq -s 'unique')"
TMP="$(mktemp)"
jq --arg c "$CANONICAL" --argjson new "$ALIAS_JSON" '
  .users = (
    (.users // [])
    | if any(.canonical == $c) then
        map(if .canonical == $c
            then .aliases = (((.aliases // []) + $new) | unique)
            else . end)
      else . + [{canonical: $c, aliases: ($new | unique)}]
      end
  )
' "$REGISTRY" > "$TMP" && mv "$TMP" "$REGISTRY"
echo "Registered in $REGISTRY"

# --- Reconcile directories created under an alias ---
# These are the per-user trees. A directory named for one of this person's
# aliases holds their work under the wrong name.
STRAY_FOUND=0
for parent in "logs/progress" "logs/audit" "notes"; do
    [[ -d "$LOG_REPO/$parent" ]] || continue
    for alias in ${ALIASES[@]+"${ALIASES[@]}"}; do
        # emails and names with spaces are never directory names; skip them
        [[ "$alias" =~ ^[A-Za-z0-9_-]+$ ]] || continue
        src="$LOG_REPO/$parent/$alias"
        dst="$LOG_REPO/$parent/$CANONICAL"
        [[ -d "$src" ]] || continue
        [[ "$src" != "$dst" ]] || continue
        STRAY_FOUND=1
        echo "STRAY  $parent/$alias  ->  $parent/$CANONICAL"
        if [[ "$APPLY" == "true" ]]; then
            mkdir -p "$dst"
            # Never clobber: a same-named file on both sides is a real conflict
            # that a human has to look at, not something to resolve silently.
            CONFLICT=0
            while IFS= read -r -d '' f; do
                rel="${f#"$src"/}"
                if [[ -e "$dst/$rel" ]]; then
                    echo "  CONFLICT: $parent/$CANONICAL/$rel already exists — left in place, not merged" >&2
                    CONFLICT=1
                else
                    mkdir -p "$dst/$(dirname "$rel")"
                    git -C "$LOG_REPO" mv "$parent/$alias/$rel" "$parent/$CANONICAL/$rel" 2>/dev/null \
                        || mv "$f" "$dst/$rel"
                fi
            done < <(find "$src" -type f -print0)
            if [[ "$CONFLICT" -eq 0 ]]; then
                find "$src" -type d -empty -delete 2>/dev/null || true
                echo "  merged"
            else
                echo "  merged what it could; conflicting files left under $parent/$alias" >&2
            fi
        fi
    done
done

if [[ "$STRAY_FOUND" -eq 0 ]]; then
    echo ""
    echo "No directories found under an alias — nothing to reconcile."
elif [[ "$APPLY" != "true" ]]; then
    echo ""
    echo "Report only. Re-run with --apply to move these."
fi

echo ""
echo "Commit identities.json (and any moves) to the knowledge repo so the rest of the"
echo "team resolves you the same way:"
echo "  bash scripts/utils/push-logs.sh"
