#!/bin/bash
set -euo pipefail

# Generate engine-specific adapter files from templates.
# Called by init-project.sh or standalone for regeneration.
#
# Usage:
#   generate-engine.sh --engine claude|codex [--project-dir PATH]
#
# For claude: generates CLAUDE.md, .claude/settings.json, .claude/commands/,
#             and .claude/skills/ wrappers (auto-generated from agents/skills/ frontmatter)
# For codex:  generates CODEX.md only

usage() {
    echo "Usage: $0 --engine <claude|codex> [--project-dir PATH]"
    echo ""
    echo "Options:"
    echo "  --engine       Engine to generate adapters for (required)"
    echo "  --project-dir  Target project directory (default: current directory)"
    exit 1
}

ENGINE=""
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine) ENGINE="$2"; shift 2 ;;
        --project-dir) PROJECT_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

[[ -z "$ENGINE" ]] && { echo "Error: --engine is required"; usage; }

# Resolve project directory
if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(pwd)"
fi

# Resolve template directory (relative to this script)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
ENGINES_DIR="$REPO_ROOT/agents/engines"
ENGINE_DIR="$ENGINES_DIR/$ENGINE"

if [[ ! -d "$ENGINE_DIR" ]]; then
    echo "Error: Unknown engine '$ENGINE'. Available engines:"
    ls -1 "$ENGINES_DIR" | grep -v README
    exit 1
fi

# --- Template substitution ---
substitute() {
    local file="$1"
    # Read PROJECT_NAME from manifest if available, otherwise use directory name
    local project_name
    if [[ -f "$PROJECT_DIR/.archetype-manifest.json" ]]; then
        project_name="$(jq -r '.template_values.PROJECT_NAME // empty' "$PROJECT_DIR/.archetype-manifest.json" 2>/dev/null || echo "")"
    fi
    if [[ -z "${project_name:-}" ]]; then
        project_name="$(basename "$PROJECT_DIR")"
    fi
    sed -i "s|{{PROJECT_NAME}}|${project_name}|g" "$file" 2>/dev/null || true
}

# --- Extract YAML frontmatter field ---
extract_frontmatter_field() {
    local file="$1" field="$2"
    # Read between first pair of --- delimiters, extract field value
    awk -v field="$field" '
        /^---$/ { delim++; next }
        delim == 1 {
            # Match field: value (value may be multi-word)
            if ($0 ~ "^" field ":") {
                sub("^" field ":[[:space:]]*", "")
                # Strip surrounding quotes if present
                gsub(/^["'\''"]|["'\''"]$/, "")
                print
                exit
            }
        }
        delim >= 2 { exit }
    ' "$file"
}

# --- Generate Claude Code adapter ---
generate_claude() {
    echo "Generating Claude Code adapter files..."

    # 1. Engine doc
    mkdir -p "$PROJECT_DIR"
    cp "$ENGINE_DIR/ENGINEDOC.md.tmpl" "$PROJECT_DIR/CLAUDE.md"
    substitute "$PROJECT_DIR/CLAUDE.md"
    echo "  CLAUDE.md"

    # 2. Settings
    mkdir -p "$PROJECT_DIR/.claude"
    cp "$ENGINE_DIR/settings.json.tmpl" "$PROJECT_DIR/.claude/settings.json"
    echo "  .claude/settings.json"

    # 3. Commands — engine-provided first, then project-level ones from
    #    agents/commands/ (engine-neutral definitions shared across engines).
    #    Without the second copy, project commands never reach a fresh clone.
    if [[ -d "$ENGINE_DIR/commands" ]] || [[ -d "$PROJECT_DIR/agents/commands" ]]; then
        mkdir -p "$PROJECT_DIR/.claude/commands"
        [[ -d "$ENGINE_DIR/commands" ]] && \
            cp "$ENGINE_DIR/commands/"*.md "$PROJECT_DIR/.claude/commands/" 2>/dev/null || true
        [[ -d "$PROJECT_DIR/agents/commands" ]] && \
            cp "$PROJECT_DIR/agents/commands/"*.md "$PROJECT_DIR/.claude/commands/" 2>/dev/null || true
        local cmd_count
        cmd_count="$(find "$PROJECT_DIR/.claude/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
        echo "  .claude/commands/ ($cmd_count commands)"
    fi

    # 4. Auto-generate skill wrappers from agents/skills/ frontmatter
    local skills_src="$PROJECT_DIR/agents/skills"
    local skills_dst="$PROJECT_DIR/.claude/skills"

    if [[ ! -d "$skills_src" ]]; then
        echo "  (no agents/skills/ directory — skipping wrapper generation)"
        return
    fi

    mkdir -p "$skills_dst"
    local count=0

    for skill_dir in "$skills_src"/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_md="$skill_dir/SKILL.md"
        [[ -f "$skill_md" ]] || continue

        local name
        name="$(extract_frontmatter_field "$skill_md" "name")"
        [[ -z "$name" ]] && continue

        local description
        description="$(extract_frontmatter_field "$skill_md" "description")"
        [[ -z "$description" ]] && continue

        mkdir -p "$skills_dst/$name"
        cat > "$skills_dst/$name/SKILL.md" << WRAPPER
---
name: ${name}
description: ${description}
---

<!-- Engine wrapper: Claude Code skill discovery -->
<!-- Full methodology: agents/skills/${name}/SKILL.md -->

Read and follow the instructions in \`agents/skills/${name}/SKILL.md\`.
WRAPPER
        count=$((count + 1))
    done

    echo "  .claude/skills/ ($count wrappers generated)"
}

# --- Generate Codex adapter ---
generate_codex() {
    echo "Generating Codex adapter files..."

    # 1. Engine doc
    mkdir -p "$PROJECT_DIR"
    cp "$ENGINE_DIR/ENGINEDOC.md.tmpl" "$PROJECT_DIR/CODEX.md"
    substitute "$PROJECT_DIR/CODEX.md"
    echo "  CODEX.md"
}

# --- Dispatch ---
case "$ENGINE" in
    claude)  generate_claude ;;
    codex)   generate_codex ;;
    *)
        echo "Error: No generation logic for engine '$ENGINE'."
        echo "Add a generate_${ENGINE}() function to this script."
        exit 1
        ;;
esac

echo "Engine adapter generation complete ($ENGINE)."
