#!/bin/bash
set -euo pipefail

# Discover agents across all registered repos and build unified registry
# Usage: scan-agents.sh [--output registry.json]


# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"
REPOS_DIR="${ROOT_DIR}/repos"
OUTPUT="${ROOT_DIR}/agents/registry.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="$2"; shift 2 ;;
        *) shift ;;
    esac
done

echo "=== Agent Registry Scan ==="

# Start building registry
REGISTRY='{"scan_timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "agents": []}'

scan_repo() {
    local repo_name="$1"
    local repo_path="$2"

    # Scan roles/ subdirectory if it exists, otherwise scan agents/ directly
    local agent_dirs=("${repo_path}/agents/roles" "${repo_path}/agents")

    for agent_dir in "${agent_dirs[@]}"; do
        [[ -d "$agent_dir" ]] || continue
        for agent_file in "${agent_dir}/"*.md; do
            [[ -f "$agent_file" ]] || continue
            local basename
            basename=$(basename "$agent_file" .md)

            # Skip non-role files
            [[ "$basename" == "README" ]] && continue
            [[ "$basename" == "AGENT_INSTRUCTIONS" ]] && continue

            # Extract mission line
            local mission=""
            mission=$(grep -m1 "^## Mission" -A2 "$agent_file" 2>/dev/null | tail -1 | sed 's/^ *//' || echo "")

            # Check for required sections
            local sections=0
            for section in "## Mission" "## Use This Role When" "## Inputs Required" "## Outputs" "## Workflow" "## Guardrails"; do
                if grep -q "^${section}" "$agent_file" 2>/dev/null; then
                    # Not ((sections++)): that returns 1 when sections is 0,
                    # which aborts this script under `set -e`.
                    sections=$((sections + 1))
                fi
            done
            local valid=$( [[ $sections -eq 6 ]] && echo "true" || echo "false" )

            REGISTRY=$(echo "$REGISTRY" | jq \
                --arg name "$basename" \
                --arg repo "$repo_name" \
                --arg path "$agent_file" \
                --arg mission "$mission" \
                --argjson valid "$valid" \
                '.agents += [{"name": $name, "repo": $repo, "path": $path, "mission": $mission, "schema_valid": $valid}]')
        done
        # Only scan first matching directory per repo
        break
    done
}

# Scan root repo agents
scan_repo "$(basename "$ROOT_DIR")" "$ROOT_DIR"

# Scan registered child repos (symlinks in repos/)
if [[ -d "$REPOS_DIR" ]]; then
    for repo_link in "$REPOS_DIR"/*/; do
        [[ -d "$repo_link" ]] || continue
        name="$(basename "$repo_link")"
        scan_repo "$name" "$repo_link"
    done
fi

# Write registry
echo "$REGISTRY" | jq '.' > "$OUTPUT"

# Summary
TOTAL=$(echo "$REGISTRY" | jq '.agents | length')
VALID=$(echo "$REGISTRY" | jq '[.agents[] | select(.schema_valid == true)] | length')
echo ""
echo "Found ${TOTAL} agent(s) across repos (${VALID} schema-valid)"
echo "Registry written to: ${OUTPUT}"

# List agents
echo ""
echo "$REGISTRY" | jq -r '.agents[] | "  \(.repo)/\(.name) \(if .schema_valid then "✓" else "✗" end) \(.mission)"'
