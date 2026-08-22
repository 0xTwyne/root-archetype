#!/bin/bash
set -euo pipefail

# Hook: check_clone_destination.sh
# Trigger: PreToolUse -> Bash
# Purpose: Block `git clone` and `git worktree add` landing outside the project.
#
# WHY ONLY CLONES
#
# check_filesystem_path.sh guards Write|Edit, where the harness hands it a
# structured file_path. Bash has no such field: deciding where an arbitrary
# command writes means deciding where an arbitrary program writes, which is not
# decidable from the command string. `python run.py --output "$OUT"`, a
# hardcoded path inside the script, or a bare open('/abs','w') are all invisible
# here, and the flag worth inspecting -- -o -- is far more often grep, find, gcc
# or sort. A guard that misfires on `grep -o` gets switched off within a day and
# then protects nothing while still looking like it does.
#
# So this does not attempt general coverage. It catches the one egress that has
# actually been observed downstream: an experiment harness and its results
# written into a sibling clone beside the root, where no other session could
# read them and the wrap-up survey -- which walks only `.` and `repos/*/` --
# could not report them as unpushed. A clone destination is an explicit argument,
# so it is decidable, and creating the clone is the step that strands the work.
#
# Script output paths remain the agent's responsibility. That gap is stated in
# agents/shared/OPERATING_CONSTRAINTS.md rather than papered over.

# --- CWD guard: silently skip if not in the project ---
if [[ ! -f "scripts/hooks/check_clone_destination.sh" ]]; then
    exit 0
fi

_LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
_ROOT="$_LIB"
while [[ "$_ROOT" != "/" && ! -f "$_ROOT/scripts/lib/cr-safe-jq.sh" ]]; do
    _ROOT="$(dirname "$_ROOT")"
done
# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
[[ -f "$_ROOT/scripts/lib/cr-safe-jq.sh" ]] && source "$_ROOT/scripts/lib/cr-safe-jq.sh"
# shellcheck source=scripts/hooks/lib/path-forms.sh
source "$_LIB/lib/path-forms.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Destinations permitted outside the project. The per-session scratchpad is the
# harness's own sanctioned temp area and is a legitimate place for a throwaway
# worktree -- without these entries this hook blocks the standard
# "worktree off origin/main, work there, remove it" workflow. Mirrors
# ALWAYS_ALLOWED in check_filesystem_path.sh; see the note there on the Windows
# forms (%TEMP% mounts at /tmp under MSYS, and TMPDIR is unset in hooks).
ALWAYS_ALLOWED=(
    "/tmp/claude-*/*"
    "${TMPDIR:-/nonexistent}/*"
    "/tmp/claude/*"
    "*/AppData/Local/Temp/claude/*"
)

INPUT="$(cat)"

# An unparseable payload must not silently disable the guard -- but it must not
# block every command either. Say so and allow, as the sibling guard does.
if ! echo "$INPUT" | jq -e . >/dev/null 2>&1; then
    echo "check_clone_destination: could not parse hook input as JSON — allowing" >&2
    exit 0
fi

COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null | tr -d '\r' || echo "")"

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Cheap pre-filter: the overwhelming majority of commands are neither, and this
# keeps them at one string test rather than a tokenize.
if [[ "$COMMAND" != *"clone"* && "$COMMAND" != *"worktree"* ]]; then
    exit 0
fi

# --- Flags that consume the following token ---
# Getting this wrong shifts the positional index and reads a flag value as the
# destination. `git clone -o upstream URL` would otherwise treat "upstream" as
# the URL and "URL" as the destination.
_clone_takes_value() {
    case "$1" in
        -b|--branch|-o|--origin|-u|--upload-pack|--depth|--reference|\
        --reference-if-able|--separate-git-dir|--template|-c|--config|\
        -j|--jobs|--filter|--shallow-since|--shallow-exclude|--server-option|\
        --bundle-uri|--revision) return 0 ;;
        *) return 1 ;;
    esac
}

_worktree_takes_value() {
    case "$1" in
        -b|-B|--reason) return 0 ;;
        *) return 1 ;;
    esac
}

# Strip one layer of surrounding quotes from a token.
_unquote() {
    local t="$1"
    if [[ ${#t} -ge 2 ]]; then
        if [[ "$t" == \"*\" || "$t" == \'*\' ]]; then
            t="${t:1:${#t}-2}"
        fi
    fi
    printf '%s\n' "$t"
}

# --- Variable expansion ---
#
# Destinations are routinely written as variables:
#   WT=/tmp/scratch/wt; git worktree add "$WT" branch
# Without expansion the guard sees the literal '$WT', resolves it against the
# project root, decides it is outside, and refuses a perfectly legal command.
# That happened on the first real use of this hook. A guard that blocks correct
# work is the one that gets switched off, so this must not fail loudly.
#
# Assignments made earlier in the same command string are collected and
# substituted. Anything still unresolved after that -- a variable from the
# environment, a nested substitution -- is NOT blocked: the destination is
# genuinely unknown, and refusing on a guess is worse than the gap. A note goes
# to stderr so the miss is visible rather than silent.
_VAR_NAMES=()
_VAR_VALS=()

_collect_assignments() {
    local tok name val
    for tok in ${_ALL[@]+"${_ALL[@]}"}; do
        if [[ "$tok" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            name="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            [[ -z "$val" ]] && continue
            _VAR_NAMES+=("$name")
            _VAR_VALS+=("$val")
        fi
    done
}

_expand_vars() {
    local s="$1" i name val
    for ((i = 0; i < ${#_VAR_NAMES[@]}; i++)); do
        name="${_VAR_NAMES[i]}"
        val="${_VAR_VALS[i]}"
        s="${s//\$\{$name\}/$val}"
        s="${s//\$$name/$val}"
    done
    s="${s//\$\{HOME\}/$HOME}"
    s="${s//\$HOME/$HOME}"
    s="${s//\$\{PWD\}/$PROJECT_DIR}"
    s="${s//\$PWD/$PROJECT_DIR}"
    printf '%s\n' "$s"
}

# Resolve "$1" against base dir "$2" and collapse . / .. lexically.
_resolve() {
    local dest="$1" base="$2"
    dest="$(_expand_vars "$dest")"
    case "$dest" in
        "~")   dest="$HOME" ;;
        "~/"*) dest="$HOME/${dest#\~/}" ;;
    esac
    if [[ "$dest" == /* || "$dest" =~ ^[A-Za-z]:[/\\] || "$dest" == \\* ]]; then
        lexical_normalize "$dest"
    else
        lexical_normalize "$base/$dest"
    fi
}

_is_allowed_outside() {
    local candidate="$1" pattern form
    collect_forms "$candidate"
    local -a forms=("${_FORMS[@]}")
    for pattern in "${ALWAYS_ALLOWED[@]}"; do
        pattern="${pattern//\\//}"
        for form in "${forms[@]}"; do
            if [[ "$form" == $pattern ]]; then
                return 0
            fi
        done
    done
    return 1
}

_refuse() {
    local kind="$1" dest="$2" raw="$3"
    # stderr, not stdout: a PreToolUse hook's stderr is what surfaces to the
    # caller on exit 2. Writing the reason to stdout surfaces as
    # "hook error: No stderr output" with nothing attached.
    echo "BLOCKED: ${kind} destination '${raw}' is outside the project." >&2
    echo "  resolves to: ${dest}" >&2
    echo "  project:     ${PROJECT_DIR}" >&2
    echo "" >&2
    echo "Work placed outside the root clone is unreadable by every other" >&2
    echo "session, and the wrap-up survey walks only '.' and 'repos/*/', so it" >&2
    echo "is never reported as unpushed either." >&2
    echo "" >&2
    echo "Use tmp/<repo>-<purpose>/ for a scratch clone (gitignored, in-tree)," >&2
    echo "or repos/<name>/ for a registered child repo." >&2
    exit 2
}

# --- Tokenize, quote-aware ---
#
# Splitting on whitespace alone loses any destination containing a space:
# `git clone URL "../my dir"` tokenizes as '"../my' and 'dir"', neither of which
# unquotes to a path, and the guard waves it through. Separators are emitted as
# their own tokens so segmentation respects quoting too -- splitting the raw
# string on ';' first would break `git clone URL "a;b"`.
#
# Fills the global _TOKENS array.
_tokenize() {
    local s="$1" i=0 ch quote="" cur="" started=0
    _TOKENS=()
    _flush() {
        if [[ $started -eq 1 ]]; then
            _TOKENS+=("$cur")
            cur=""; started=0
        fi
    }
    while [[ $i -lt ${#s} ]]; do
        ch="${s:i:1}"
        if [[ -n "$quote" ]]; then
            if [[ "$ch" == "$quote" ]]; then quote=""; else cur+="$ch"; fi
            started=1
        elif [[ "$ch" == '"' || "$ch" == "'" ]]; then
            quote="$ch"; started=1
        elif [[ "$ch" == [[:space:]] ]]; then
            _flush
        elif [[ "$ch" == ";" ]]; then
            _flush; _TOKENS+=(";")
        elif [[ "$ch" == "&" || "$ch" == "|" ]]; then
            _flush
            if [[ "${s:i+1:1}" == "$ch" ]]; then i=$((i + 1)); fi
            _TOKENS+=(";")
        elif [[ "$ch" == $'\n' ]]; then
            _flush; _TOKENS+=(";")
        else
            cur+="$ch"; started=1
        fi
        i=$((i + 1))
    done
    _flush
}

# --- Walk the command, tracking cwd across cd and git -C ---
#
# A relative destination is resolved against whatever `cd` most recently
# established, so `cd /elsewhere && git clone URL sibling` is caught rather than
# resolved against the project root and waved through.
CURRENT_DIR="$PROJECT_DIR"

_tokenize "$COMMAND"
_ALL=("${_TOKENS[@]+"${_TOKENS[@]}"}")
_collect_assignments

# Regroup into segments on the ';' separator tokens.
_segment_tokens=()
_idx=0
while :; do
    tokens=()
    while [[ $_idx -lt ${#_ALL[@]} && "${_ALL[$_idx]}" != ";" ]]; do
        tokens+=("${_ALL[$_idx]}")
        _idx=$((_idx + 1))
    done
    _more=0
    if [[ $_idx -lt ${#_ALL[@]} ]]; then
        _idx=$((_idx + 1))
        _more=1
    fi

    # An empty segment with nothing left to read is the loop's exit. Every
    # `continue` below lands here on the next pass, so they terminate too.
    if [[ ${#tokens[@]} -eq 0 ]]; then
        if [[ $_more -eq 1 ]]; then
            continue
        fi
        break
    fi

    # Track cd. Only a bare `cd <path>` -- `cd` with no argument goes HOME, and
    # `cd -` is a history move this does not model.
    if [[ "${tokens[0]}" == "cd" ]]; then
        if [[ ${#tokens[@]} -ge 2 ]]; then
            _target="$(_unquote "${tokens[1]}")"
            if [[ "$_target" != "-" ]]; then
                CURRENT_DIR="$(_resolve "$_target" "$CURRENT_DIR")"
            fi
        else
            CURRENT_DIR="$HOME"
        fi
        continue
    fi

    # Find a `git` token; anything before it (env assignments, sudo) is skipped.
    gi=-1
    for ((i = 0; i < ${#tokens[@]}; i++)); do
        if [[ "${tokens[i]}" == "git" || "${tokens[i]}" == *"/git" ]]; then
            gi=$i
            break
        fi
    done
    [[ $gi -lt 0 ]] && continue

    # git -C <path> relocates git itself for this invocation.
    base_dir="$CURRENT_DIR"
    sub=""
    sub_idx=-1
    for ((i = gi + 1; i < ${#tokens[@]}; i++)); do
        tok="${tokens[i]}"
        if [[ "$tok" == "-C" ]]; then
            if [[ $((i + 1)) -lt ${#tokens[@]} ]]; then
                base_dir="$(_resolve "$(_unquote "${tokens[i+1]}")" "$base_dir")"
                i=$((i + 1))
            fi
            continue
        fi
        if [[ "$tok" == -* ]]; then
            continue
        fi
        sub="$tok"
        sub_idx=$i
        break
    done

    dest_raw=""
    kind=""

    if [[ "$sub" == "clone" ]]; then
        kind="git clone"
        positionals=()
        for ((i = sub_idx + 1; i < ${#tokens[@]}; i++)); do
            tok="${tokens[i]}"
            if [[ "$tok" == --*=* ]]; then
                continue
            fi
            if [[ "$tok" == -* ]]; then
                if _clone_takes_value "$tok"; then
                    i=$((i + 1))
                fi
                continue
            fi
            positionals+=("$(_unquote "$tok")")
        done
        if [[ ${#positionals[@]} -ge 2 ]]; then
            dest_raw="${positionals[1]}"
        elif [[ ${#positionals[@]} -eq 1 ]]; then
            # No explicit destination: git derives it from the URL and creates it
            # in the current directory.
            url="${positionals[0]}"
            url="${url%/}"
            url="${url##*/}"
            url="${url%.git}"
            dest_raw="$url"
        fi

    elif [[ "$sub" == "worktree" ]]; then
        # Only `worktree add` creates a path; list/remove/prune do not.
        wt_add=-1
        for ((i = sub_idx + 1; i < ${#tokens[@]}; i++)); do
            if [[ "${tokens[i]}" == "add" ]]; then
                wt_add=$i
                break
            fi
        done
        [[ $wt_add -lt 0 ]] && continue
        kind="git worktree add"
        for ((i = wt_add + 1; i < ${#tokens[@]}; i++)); do
            tok="${tokens[i]}"
            if [[ "$tok" == --*=* ]]; then
                continue
            fi
            if [[ "$tok" == -* ]]; then
                if _worktree_takes_value "$tok"; then
                    i=$((i + 1))
                fi
                continue
            fi
            dest_raw="$(_unquote "$tok")"
            break
        done
    fi

    [[ -z "$dest_raw" ]] && continue

    resolved="$(_resolve "$dest_raw" "$base_dir")"

    # Still carrying an unexpanded reference: the destination is unknowable
    # here. Say so and allow, rather than refusing correct work on a guess.
    if [[ "$resolved" == *'$'* || "$resolved" == *'`'* ]]; then
        echo "check_clone_destination: '${dest_raw}' contains an unresolved" \
             "variable; cannot verify it stays inside the project — allowing." >&2
        continue
    fi

    if path_is_within "$resolved" "$PROJECT_DIR"; then
        continue
    fi
    if _is_allowed_outside "$resolved"; then
        continue
    fi

    _refuse "$kind" "$resolved" "$dest_raw"

done

exit 0
