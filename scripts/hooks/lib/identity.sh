#!/usr/bin/env bash
# User identity canonicalisation — sourced by hook-utils.sh.
#
# One person must map to exactly ONE directory name. Without this, the fallback
# chain in session-start (gh login -> git user.name -> $USER -> "unknown", then
# sanitised to [a-zA-Z0-9_-]) hands the same person a different name depending on
# which fallback fired and which machine they are on:
#
#   gh authenticated        -> "dmrobotix"
#   gh missing, git config  -> "MargotPaez"   (from "Margot Paez")
#   neither                 -> "margot"       (from $USER)
#
# All three are the same human. Nothing errors; their logs, notes and handoffs
# simply split across three directories that nobody thinks to merge, and the
# per-user isolation rule silently stops meaning anything.
#
# The registry lives in the log repo at identities.json, because that is where
# the per-user directories it governs live.

# --- Canonicalise a raw username ---
# Usage: hook_canonical_user <raw-name>
# Echoes the canonical name, or the raw name unchanged when no mapping applies.
# Never fails: an unregistered user is normal (they register on first session).

# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

hook_canonical_user() {
  local raw="${1:-}"
  [[ -n "$raw" ]] || { echo ""; return 0; }

  hook_resolve_log_repo 2>/dev/null || { echo "$raw"; return 0; }
  local registry="${LOG_REPO_DIR:-}/identities.json"
  [[ -f "$registry" ]] || { echo "$raw"; return 0; }
  command -v jq >/dev/null 2>&1 || { echo "$raw"; return 0; }

  # Everything this person could currently present as. Compared
  # case-insensitively, so "AdaLovelace" matches "adalovelace".
  local gh_login git_name git_email
  gh_login="$(gh api user --jq '.login' 2>/dev/null || echo "")"
  git_name="$(git config user.name 2>/dev/null || echo "")"
  git_email="$(git config user.email 2>/dev/null || echo "")"

  local canonical
  canonical="$(jq -r --arg raw "$raw" --arg gh "$gh_login" --arg gn "$git_name" \
                     --arg ge "$git_email" --arg u "${USER:-}" '
    def norm: ascii_downcase | gsub("[^a-z0-9_@.-]"; "");
    # Parenthesised so the binding does not pipe the array onward — otherwise
    # `.users` is evaluated against the array instead of the document and every
    # lookup silently returns nothing.
    ([$raw, $gh, $gn, $ge, $u] | map(select(. != "")) | map(norm)) as $mine
    | [ .users[]?
        | select(
            (([.canonical // ""] + (.aliases // [])) | map(norm)
             | any(. as $a | $mine | index($a) != null))
          )
        | .canonical ]
    | first // ""
  ' "$registry" 2>/dev/null || echo "")"

  if [[ -n "$canonical" && "$canonical" != "null" ]]; then
    echo "$canonical"
  else
    echo "$raw"
  fi
}

# --- Warn when a user looks unregistered and ambiguous ---
# Usage: hook_identity_warning <resolved-name>
# Echoes a warning string (or nothing). Only fires when the person is NOT in the
# registry AND their identity could plausibly resolve differently elsewhere —
# there is no value in nagging someone whose gh login is the only thing present.
hook_identity_warning() {
  local name="${1:-}"
  [[ -n "$name" ]] || return 0

  hook_resolve_log_repo 2>/dev/null || return 0
  local registry="${LOG_REPO_DIR:-}/identities.json"
  [[ -f "$registry" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local known
  known="$(jq -r --arg n "$name" '
    def norm: ascii_downcase;
    [ .users[]? | select(((.canonical // "") | norm) == ($n | norm)) ] | length
  ' "$registry" 2>/dev/null || echo "0")"
  [[ "$known" == "0" ]] || return 0

  # Would another machine resolve this person differently?
  local gh_login git_name
  gh_login="$(gh api user --jq '.login' 2>/dev/null || echo "")"
  git_name="$(git config user.name 2>/dev/null || echo "")"
  local sanitized_git
  sanitized_git="$(printf '%s' "$git_name" | tr -cd 'a-zA-Z0-9_-')"

  if [[ -z "$gh_login" ]]; then
    echo "IDENTITY: gh is not authenticated, so '$name' came from a fallback. On a machine where gh works you would be a different user directory. Run: bash scripts/utils/register-identity.sh"
  elif [[ -n "$sanitized_git" && "$sanitized_git" != "$gh_login" ]]; then
    echo "IDENTITY: '$name' is not in identities.json, and your git name would resolve to '$sanitized_git' if gh were unavailable. Register both so your history stays in one directory: bash scripts/utils/register-identity.sh"
  fi
}
