#!/bin/bash
set -euo pipefail

# Hook: check_secrets_read.sh
# Trigger: PreToolUse → Read|Glob|Grep|Bash
# Purpose: Block read access to protected secret paths
#
# Config: secrets/.secretpaths (one pattern per line)

# --- Resolve project dir ---
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

# --- Source hook utilities ---
HOOK_LIB="${PROJECT_DIR}/scripts/hooks/lib/hook-utils.sh"
if [[ -f "$HOOK_LIB" ]]; then
    source "$HOOK_LIB"
else
    # Minimal fallback if hook-utils not available
    hook_fail_open() { exit 0; }
    hook_block() { echo "{\"decision\":\"block\",\"reason\":\"$1\"}" | jq -c .; exit 2; }
    hook_silent() { exit 0; }
fi

# --- Load config ---
CONFIG_FILE="${PROJECT_DIR}/secrets/.secretpaths"
if [[ ! -f "$CONFIG_FILE" ]]; then
    hook_fail_open "check_secrets_read" "No secrets/.secretpaths config found"
fi

# Parse patterns from config (skip comments and blank lines)
PATTERNS=()
while IFS= read -r line; do
    line="${line%%#*}"         # Strip inline comments
    line="${line#"${line%%[![:space:]]*}"}"  # Trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"  # Trim trailing whitespace
    [[ -z "$line" ]] && continue
    # Expand ~ to HOME
    line="${line/#\~/$HOME}"
    PATTERNS+=("$line")
done < "$CONFIG_FILE"

if [[ ${#PATTERNS[@]} -eq 0 ]]; then
    hook_silent
fi

# --- Read tool input from stdin ---
# The harness delivers one JSON object on stdin: {tool_name, tool_input:{...}}.
# This hook previously took the tool name from $CLAUDE_TOOL_NAME, which the
# harness does not set, so TOOL_NAME was always empty, the case below fell
# through to *) and the guard never blocked anything. It also read the path
# fields from the TOP level of that object rather than from .tool_input, so
# even a correct tool name yielded an empty path. Either fault alone disabled
# the guard completely. Both shapes are accepted now.
HOOK_INPUT="$(cat)"
TOOL_NAME="$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")"
[[ -z "$TOOL_NAME" ]] && TOOL_NAME="${CLAUDE_TOOL_NAME:-}"

# Prefer .tool_input, fall back to the whole object for the flat shape.
TOOL_INPUT="$(echo "$HOOK_INPUT" | jq -c '.tool_input // .' 2>/dev/null || echo '{}')"
[[ -z "$TOOL_INPUT" || "$TOOL_INPUT" == "null" ]] && TOOL_INPUT='{}'

# An unparseable payload must not silently disable the guard.
if ! echo "$HOOK_INPUT" | jq -e . >/dev/null 2>&1; then
    hook_fail_open "check_secrets_read" "could not parse hook input as JSON"
fi

# --- Path matching function ---
# Returns 0 if path matches any protected pattern
path_matches_secret() {
    local check_path="$1"

    # Resolve to absolute path
    if [[ "$check_path" != /* ]]; then
        check_path="${PROJECT_DIR}/${check_path}"
    fi

    # Resolve symlinks (best effort)
    check_path="$(realpath -m "$check_path" 2>/dev/null || echo "$check_path")"

    for pattern in "${PATTERNS[@]}"; do
        # Convert pattern to absolute if relative
        local abs_pattern="$pattern"
        if [[ "$abs_pattern" != /* ]]; then
            abs_pattern="${PROJECT_DIR}/${abs_pattern}"
        fi

        # Shell glob match
        # shellcheck disable=SC2254
        case "$check_path" in
            $abs_pattern) return 0 ;;
        esac

        # Directory prefix check: if check_path is a parent dir of a protected pattern
        # e.g., "secrets/" is a parent of "secrets/*"
        local pattern_dir
        pattern_dir="$(dirname "$abs_pattern")"
        local clean_path="${check_path%/}"
        if [[ "$clean_path" == "$pattern_dir" ]]; then
            return 0
        fi

        # Also check basename for extension patterns (*.pem, *.key, etc.)
        if [[ "$pattern" == \*.* ]]; then
            local basename
            basename="$(basename "$check_path")"
            # shellcheck disable=SC2254
            case "$basename" in
                $pattern) return 0 ;;
            esac
        fi

        # Check if path contains pattern segments (for patterns like *id_rsa*)
        if [[ "$pattern" == \** && "$pattern" == *\* ]]; then
            local inner="${pattern#\*}"
            inner="${inner%\*}"
            if [[ "$check_path" == *"$inner"* ]]; then
                return 0
            fi
        fi
    done

    return 1
}

block_secret_access() {
    local path="$1"
    hook_block "BLOCKED: Read access to protected path: ${path}. Secrets are not accessible to AI agents. See secrets/.secretpaths for the protected path list."
}

# --- Extract and check paths based on tool type ---
case "$TOOL_NAME" in
    Read)
        FILE_PATH="$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)"
        if [[ -n "$FILE_PATH" ]] && path_matches_secret "$FILE_PATH"; then
            block_secret_access "$FILE_PATH"
        fi
        ;;

    Glob)
        GLOB_PATTERN="$(echo "$TOOL_INPUT" | jq -r '.pattern // empty' 2>/dev/null)"
        GLOB_PATH="$(echo "$TOOL_INPUT" | jq -r '.path // empty' 2>/dev/null)"

        # Check if glob path targets a secret directory
        if [[ -n "$GLOB_PATH" ]] && path_matches_secret "$GLOB_PATH"; then
            block_secret_access "$GLOB_PATH"
        fi
        # Check if glob pattern would match secret paths
        if [[ -n "$GLOB_PATTERN" ]]; then
            for pattern in "${PATTERNS[@]}"; do
                # If the glob pattern starts with a secret directory
                local abs_pattern="$pattern"
                [[ "$abs_pattern" != /* ]] && abs_pattern="${PROJECT_DIR}/${abs_pattern}"
                local secret_dir
                secret_dir="$(dirname "$abs_pattern")"
                # Check if glob targets this secret dir
                local check_glob="$GLOB_PATTERN"
                [[ "$check_glob" != /* ]] && check_glob="${PROJECT_DIR}/${check_glob}"
                check_glob="$(realpath -m "$(dirname "$check_glob")" 2>/dev/null || echo "$check_glob")"
                if [[ "$check_glob" == "$secret_dir"* ]]; then
                    block_secret_access "$GLOB_PATTERN"
                fi
            done
        fi
        ;;

    Grep)
        GREP_PATH="$(echo "$TOOL_INPUT" | jq -r '.path // empty' 2>/dev/null)"
        if [[ -n "$GREP_PATH" ]] && path_matches_secret "$GREP_PATH"; then
            block_secret_access "$GREP_PATH"
        fi
        ;;

    Bash)
        COMMAND="$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)"
        if [[ -z "$COMMAND" ]]; then
            hook_silent
        fi

        # Commands that read file contents
        READ_CMDS='cat|head|tail|less|more|sed|awk|grep|rg|bat|strings|xxd|od|hexdump'
        # Commands that copy from a source
        COPY_CMDS='cp|scp|rsync|mv'
        # Source/include commands
        SOURCE_CMDS='source|\.'
        # curl with file upload
        CURL_FILE='curl.*(-d\s+@|--data-binary\s+@|--data\s+@|--upload-file)'

        for pattern in "${PATTERNS[@]}"; do
            abs_pattern="$pattern"
            [[ "$abs_pattern" != /* ]] && abs_pattern="${PROJECT_DIR}/${abs_pattern}"

            # For glob patterns, extract the directory or literal part
            # e.g., "secrets/*" → check for "secrets/" in command
            literal_part="${abs_pattern%%\**}"
            # Also check with relative path
            rel_pattern="${pattern%%\**}"

            # Skip patterns that reduce to empty after glob stripping
            [[ -z "$literal_part" && -z "$rel_pattern" ]] && continue

            # Use fixed-string grep to avoid regex issues with glob chars
            for search_str in "$literal_part" "$rel_pattern"; do
                [[ -z "$search_str" ]] && continue
                if echo "$COMMAND" | grep -qF "$search_str"; then
                    # Confirmed the path appears in command — now check it's a file operation
                    if echo "$COMMAND" | grep -qE "(${READ_CMDS}|${COPY_CMDS}|source|curl)"; then
                        block_secret_access "$pattern (in bash command)"
                    fi
                fi
            done
        done
        ;;

    *)
        # Unknown tool — no action
        ;;
esac

hook_silent
