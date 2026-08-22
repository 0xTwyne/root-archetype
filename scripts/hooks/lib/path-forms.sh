#!/usr/bin/env bash
# Path comparison helpers shared by the filesystem guards.
#
# Two problems, both learned the hard way in check_filesystem_path.sh:
#
# 1. FORM. The harness reports paths in the platform's native shape; on Windows
#    that is a backslashed drive path (C:\Users\me\repo), while PROJECT_DIR and
#    pwd read from inside MSYS bash are POSIX (/c/Users/me/repo). Comparing them
#    as plain strings matched nothing, so the guard blocked every write into the
#    project and reported it on stdout, where a PreToolUse caller never sees it.
#    Rather than elect a canonical form, emit every legitimate form and compare
#    all of them.
#
# 2. ANCHORING. A bare "${allowed}"* prefix test also admits siblings whose name
#    merely starts with the allowed root: with /c/Users/me/proj allowed,
#    /c/Users/me/proj-evil/x passed as though it were inside the project.
#    The prefix has to end on a separator.
#
# These live here rather than in check_filesystem_path.sh so a second guard can
# use them without editing that file. check_filesystem_path.sh still carries its
# own private copies; point it at this file when convenient and delete them.

# The separators live in variables because both inline spellings are broken.
# Writing the search term as an escaped backslash followed immediately by the
# replacement delimiter makes bash read the whole thing as "delete every forward
# slash" -- that is what turned the glob */.claude/* into *.claude*. Escaping the
# replacement slash instead yields a no-op. sed and tr both mangle backslashes in
# argv under MSYS, so neither is an option either.
_PF_BSLASH='\'
_PF_FSLASH='/'

# Emit every comparison form of "$1", one per line.
path_forms() {
    printf '%s\n' "${1//"$_PF_BSLASH"/"$_PF_FSLASH"}"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m -- "$1" 2>/dev/null || true
        cygpath -u -- "$1" 2>/dev/null || true
    fi
}

# Sets _FORMS to the deduplicated comparison forms of "$1".
collect_forms() {
    local _f
    _FORMS=()
    while IFS= read -r _f; do
        if [[ -n "$_f" ]]; then
            _FORMS+=("$_f")
        fi
    done < <(path_forms "$1")
}

# Collapse . and .. lexically, without touching the filesystem.
#
# check_filesystem_path.sh deliberately does NOT do this: it judges a path by
# the string it arrives as, because Write creates paths that do not exist yet and
# canonicalizing them is its own problem. That trade-off is wrong for a clone
# destination. `git clone <url> ../sibling` run from /workspace yields the string
# /workspace/../sibling, which passes an anchored /workspace/ prefix test while
# landing outside the project -- a false negative on precisely the case the
# clone guard exists to catch. Lexical collapsing needs no filesystem access and
# closes it.
#
# Still textual: a symlink crossing out of the project is judged by its spelling.
lexical_normalize() {
    local path="$1" prefix="" part
    local -a out=()

    path="${path//"$_PF_BSLASH"/"$_PF_FSLASH"}"

    # Preserve a leading / or a C:/ drive so the rebuild does not relativize it.
    if [[ "$path" == /* ]]; then
        prefix="/"
    elif [[ "$path" =~ ^([A-Za-z]:)/ ]]; then
        prefix="${BASH_REMATCH[1]}/"
        path="${path#??}"
    fi

    local IFS='/'
    # Unquoted on purpose: this is the word split that yields the components.
    # shellcheck disable=SC2206
    local -a parts=($path)
    for part in ${parts[@]+"${parts[@]}"}; do
        case "$part" in
            ''|'.') ;;
            '..')
                # Popping past the root leaves it at the root, as the kernel does.
                if [[ ${#out[@]} -gt 0 && "${out[${#out[@]}-1]}" != ".." ]]; then
                    unset 'out[${#out[@]}-1]'
                elif [[ -z "$prefix" ]]; then
                    out+=("..")
                fi
                ;;
            *) out+=("$part") ;;
        esac
    done

    local joined=""
    if [[ ${#out[@]} -gt 0 ]]; then
        joined="${out[*]}"
    fi

    if [[ -n "$prefix" ]]; then
        printf '%s%s\n' "$prefix" "$joined"
    elif [[ -n "$joined" ]]; then
        printf '%s\n' "$joined"
    else
        printf '.\n'
    fi
}

# True if "$1" is at or under "$2", comparing every form of each.
path_is_within() {
    local candidate="$1" root="$2" cand_form root_form
    local -a cand_forms

    collect_forms "$candidate"
    cand_forms=("${_FORMS[@]}")

    collect_forms "$root"
    for root_form in "${_FORMS[@]}"; do
        for cand_form in "${cand_forms[@]}"; do
            if [[ "$cand_form" == "$root_form" || "$cand_form" == "${root_form%/}/"* ]]; then
                return 0
            fi
        done
    done
    return 1
}
