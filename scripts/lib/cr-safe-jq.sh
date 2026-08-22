#!/usr/bin/env bash
# CR-safe jq — source this before any jq use.
#
# The Windows (winget / MSYS-native) jq build writes stdout in text mode, so
# every LF it emits becomes CRLF. Command substitution strips the trailing LF
# but not the CR, so `$(jq -r .log_repo_name manifest.json)` yields
# "sangha-knowledge\r" — a name that matches no directory, names no repo, and
# corrupts any URL built from it. Nothing errors; the value is simply wrong.
#
# Connor-03 found and fixed six call sites this way (PR #29). There were sixty.
# Patching them one at a time leaves the next `jq` anyone writes exposed, which
# is the same "manage the problem vs remove it" trap this repo has hit before —
# so the fix is one wrapper every script inherits, not sixty pipes.
#
# Semantics deliberately preserved, all verified with and without `pipefail`:
#
#   - value capture      X="$(jq -r .a f)"        -> CR stripped
#   - JSON generation    jq -cn --arg ...         -> works, CR stripped
#   - validity checks    if ! ... | jq -e . ;     -> jq's own status is returned
#   - fallbacks          $(jq ... || echo FB)     -> fires when jq fails
#   - read loops         done < <(jq -r ...)      -> streams normally
#
# `return "${PIPESTATUS[0]}"` is what makes `jq -e` and `||` fallbacks keep
# working: without it the pipeline reports `tr`'s status (always 0) unless the
# caller happens to set `pipefail`, and malformed JSON would read as valid.
#
# On Linux and macOS `tr -d '\r'` is a no-op, so this costs one process and
# changes nothing.

jq() {
    command jq "$@" | tr -d '\r'
    return "${PIPESTATUS[0]}"
}
