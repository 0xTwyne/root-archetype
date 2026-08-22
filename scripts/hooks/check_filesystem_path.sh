#!/bin/bash
set -euo pipefail

# Hook: check_filesystem_path.sh
# Trigger: PreToolUse → Write|Edit
# Purpose: Block writes outside approved paths
#
# Configure ALLOWED_PATHS in this script for your project.

# --- CWD guard: silently skip if not in sangha-root ---

# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

if [[ ! -f "scripts/hooks/check_filesystem_path.sh" ]]; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Extra roots to permit beyond the project itself. PROJECT_DIR is appended
# below: without that default this list is empty, so once the guard actually
# receives a path it would block every write to the project, including its own
# scripts. The guard exists to stop writes OUTSIDE the project.
ALLOWED_PATHS=(
    # Add extra allowed roots here, e.g.:
    # "/opt/data/"
)

# Always allow .claude config directories, and the per-session scratchpad the
# harness tells agents to use for temporary files. The scratchpad lives outside
# the project by design, so without this entry every scratch write is blocked
# the moment this guard starts working.
# On Windows none of the first three entries can match. The harness puts the
# scratchpad at %TEMP%\claude\<project>\<session>\scratchpad; MSYS mounts %TEMP%
# at /tmp, so cygpath renders that path as /tmp/claude/... — directory "claude",
# which /tmp/claude-*/* does not match — and TMPDIR is not set in the hook's
# environment at all, leaving that entry as the literal /nonexistent/*. The last
# two entries cover the Windows scratchpad in both of the forms it can arrive in.
ALWAYS_ALLOWED=(
    "*/.claude/*"
    "/tmp/claude-*/*"
    "${TMPDIR:-/nonexistent}/*"
    "/tmp/claude/*"
    "*/AppData/Local/Temp/claude/*"
)

# Extract file_path from tool input (one JSON object on stdin).
# The harness sends {tool_name, tool_input:{file_path,...}}. This read
# .file_path from the TOP level, which is never populated in that shape, so
# FILE_PATH was always empty and the guard skipped every write. Accept the
# nested shape first, then the flat one for back-compat.
#
# tr -d '\r': the Windows jq build writes stdout in text mode, so a bare CR
# rides along on every value and survives $( ). A path ending in CR matches no
# prefix and no glob.
INPUT="$(cat)"
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .file_path // .path // empty' 2>/dev/null | tr -d '\r' || echo "")"

# An unparseable payload must not silently disable the guard.
if ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    echo "check_filesystem_path: could not parse hook input as JSON — allowing" >&2
    exit 0
fi

if [[ -z "$FILE_PATH" ]]; then
    exit 0  # No file_path in input — not our concern
fi

# --- Path form normalization (Windows) ---
# The harness reports file_path in the platform's native form; on Windows that
# is a backslashed drive path (C:\Users\me\repo\file). PROJECT_DIR and pwd, read
# from inside MSYS bash, are POSIX-style (/c/Users/me/repo). The prefix and glob
# tests below compare the two as plain strings, so on Windows nothing ever
# matched: this guard blocked every write into the project — including edits to
# its own source — and said so on stdout, where a PreToolUse caller never sees
# it. The failure read as a hook crash with no reason attached.
#
# Rather than elect one canonical form, emit every form a path can legitimately
# take and compare all of them. Globs are only slash-flipped, never passed
# through cygpath, which would eat the wildcards.
#
# The separators live in variables because both inline spellings are broken, and
# they are described here rather than written out so nobody mistakes the example
# for working code. Writing the search term as an escaped backslash followed
# immediately by the replacement delimiter makes bash read the whole thing as
# "delete every forward slash": that is what turned the glob */.claude/* into
# *.claude* and left cygpath as the only thing actually normalizing anything.
# Escaping the replacement slash instead yields a no-op. The variable form below
# behaves, and costs no subprocess; sed and tr both mangle backslashes in argv
# under MSYS.
#
# Known gap, deliberately left open: comparison is textual. A path containing ..
# or crossing a symlink is judged by the string it arrives as, not by where it
# resolves to. Canonicalizing would mean resolving paths that do not exist yet —
# Write creates them — which is its own problem, so it is not attempted here.
_BSLASH='\'
_FSLASH='/'

_path_forms() {
    printf '%s\n' "${1//"$_BSLASH"/"$_FSLASH"}"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m -- "$1" 2>/dev/null || true
        cygpath -u -- "$1" 2>/dev/null || true
    fi
}

# Sets _FORMS to the deduplicated comparison forms of "$1".
_collect_forms() {
    local _f
    _FORMS=()
    while IFS= read -r _f; do
        if [[ -n "$_f" ]]; then
            _FORMS+=("$_f")
        fi
    done < <(_path_forms "$1")
}

_collect_forms "$FILE_PATH"
FILE_FORMS=("${_FORMS[@]}")

# Check always-allowed patterns
for pattern in "${ALWAYS_ALLOWED[@]}"; do
    pattern="${pattern//"$_BSLASH"/"$_FSLASH"}"
    for form in "${FILE_FORMS[@]}"; do
        if [[ "$form" == $pattern ]]; then
            exit 0
        fi
    done
done

# The project directory is always an allowed write target.
ALLOWED_PATHS+=("$PROJECT_DIR")

# Check allowed paths
for allowed in ${ALLOWED_PATHS[@]+"${ALLOWED_PATHS[@]}"}; do
    _collect_forms "$allowed"
    for allowed_form in "${_FORMS[@]}"; do
        for form in "${FILE_FORMS[@]}"; do
            # The prefix has to end on a separator. A bare "${allowed_form}"*
            # also admits siblings whose name merely starts with the allowed
            # root: with /c/Users/me/sangha-root allowed, a write to
            # /c/Users/me/sangha-root-evil/x passed as though it were inside the
            # project. Any trailing slash on the allowed root is stripped first
            # so entries written either way behave the same.
            if [[ "$form" == "$allowed_form" || "$form" == "${allowed_form%/}/"* ]]; then
                exit 0
            fi
        done
    done
done

# stderr, not stdout: a PreToolUse hook's stderr is what surfaces to the caller
# on exit 2.
echo "BLOCKED: Write to ${FILE_PATH} is outside allowed paths." >&2
echo "Allowed: ${ALLOWED_PATHS[*]}" >&2
exit 2
