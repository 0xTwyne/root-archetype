#!/bin/bash
set -euo pipefail

# Check a secret-reference env file: the tracked template (or host reference
# file) that maps env vars to keystore references, e.g.
#     DEPLOY_TOKEN=op://my-vault/DEPLOY_TOKEN/password
#
# Default mode -- the file must hold references only:
#   - no value matches a pattern in scripts/hooks/lib/secret-patterns.txt
#   - a credential-named key (…_KEY, …TOKEN…, …SECRET…, …PASSWORD…, …PRIVATE…,
#     …CREDENTIAL…) is empty or a reference, never a literal value
#   - every op:// reference is well formed: op://<vault>/<item>/[<section>/]<field>
#     with no spaces or brackets. Checked in comment lines too, because
#     `op inject` resolves references inside comments and fails on a bad one.
#
# --resolved -- run on the OUTPUT of an inject step (CI deploy, launcher):
#   - no reference is left unresolved on a non-comment line
#
# Output names file:line and KEY only. It never prints a value.
#
# Usage: check_secret_refs.sh [--resolved] FILE...
# Reference prefixes: SECRET_REF_PREFIXES (space-separated, default "op://").
# Exit: 0 clean, 1 violations, 2 usage error.

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PATTERNS_FILE="$ROOT/scripts/hooks/lib/secret-patterns.txt"
read -r -a PREFIXES <<< "${SECRET_REF_PREFIXES:-op://}"

MODE="template"
if [[ "${1:-}" == "--resolved" ]]; then MODE="resolved"; shift; fi
if [[ $# -eq 0 ]]; then
    echo "usage: check_secret_refs.sh [--resolved] FILE..." >&2
    exit 2
fi

CRED_NAME_RE='(_KEY$|_KEY_|^KEY$|TOKEN|SECRET|PASSWORD|PASSWD|PRIVATE|CREDENTIAL)'
OP_REF_RE='^op://[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+){1,2}$'

is_ref() {
    local v="$1" p
    for p in "${PREFIXES[@]}"; do [[ "$v" == "$p"* ]] && return 0; done
    return 1
}

matches_secret_pattern() {
    local v="$1" label rx _
    [[ -f "$PATTERNS_FILE" ]] || return 1
    while IFS=$'\t' read -r label rx _; do
        [[ -z "$label" || "$label" == \#* || -z "$rx" ]] && continue
        if printf '%s' "$v" | grep -Eq -- "$rx" 2>/dev/null; then
            printf '%s' "$label"
            return 0
        fi
    done < "$PATTERNS_FILE"
    return 1
}

VIOLATIONS=0
report() { VIOLATIONS=$((VIOLATIONS + 1)); printf '%s:%s: %s\n' "$1" "$2" "$3"; }

for file in "$@"; do
    if [[ ! -f "$file" ]]; then
        echo "check_secret_refs: no such file: $file" >&2
        exit 2
    fi
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        trimmed="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$trimmed" ]] && continue

        if [[ "$trimmed" == \#* ]]; then
            if [[ "$MODE" == "template" ]]; then
                for tok in $(grep -oE 'op://[^[:space:]"'"'"']*' <<< "$trimmed" || true); do
                    [[ "$tok" =~ $OP_REF_RE ]] || report "$file" "$n" "malformed op:// reference in a comment (op inject still resolves it)"
                done
            fi
            continue
        fi

        trimmed="${trimmed#export }"
        if [[ "$trimmed" != *=* ]]; then
            report "$file" "$n" "not a KEY=VALUE line"
            continue
        fi
        key="${trimmed%%=*}"
        value="${trimmed#*=}"
        value="${value%\"}"; value="${value#\"}"
        value="${value%\'}"; value="${value#\'}"

        if [[ "$MODE" == "resolved" ]]; then
            is_ref "$value" && report "$file" "$n" "$key: reference left unresolved"
            continue
        fi

        [[ -z "$value" ]] && continue
        if is_ref "$value"; then
            if [[ "$value" == op://* && ! "$value" =~ $OP_REF_RE ]]; then
                report "$file" "$n" "$key: malformed op:// reference (spaces, brackets or wrong depth)"
            fi
            continue
        fi
        if label="$(matches_secret_pattern "$value")"; then
            report "$file" "$n" "$key: literal value matches secret pattern '$label'"
            continue
        fi
        if [[ "$(tr '[:lower:]' '[:upper:]' <<< "$key")" =~ $CRED_NAME_RE ]]; then
            report "$file" "$n" "$key: credential-named key holds a literal value, not a reference"
        fi
    done < "$file"
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo "check_secret_refs: $VIOLATIONS violation(s)"
    exit 1
fi
echo "check_secret_refs: OK ($MODE, $# file(s))"
