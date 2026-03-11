#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
source "$PROJECT_DIR/.claude/hooks/lib/hook-utils.sh" 2>/dev/null || true

set -euo pipefail

# Hook: UserPromptSubmit
# Detects user corrections and prompts the agent to assess whether the
# correction reveals a gap in an agent file (CLAUDE.md, agents/*.md).

command -v jq >/dev/null 2>&1 || exit 0

hook_load_identity

INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")"
PROMPT="$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || echo "")"

[[ -z "$PROMPT" ]] && exit 0

PROMPT_LOWER="$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')"

# Exclude verification questions (prevent false positives)
if echo "$PROMPT_LOWER" | grep -qE '(is that correct|are you sure|can you verify|could you check)'; then
  exit 0
fi

# --- Correction pattern groups ---
MATCH=0

# Group 1: Explicit corrections
echo "$PROMPT_LOWER" | grep -qE "(that'?s wrong|that'?s incorrect|you'?re mistaken|that'?s not right)" && MATCH=1

# Group 2: Corrective statements
[[ $MATCH -eq 0 ]] && echo "$PROMPT_LOWER" | grep -qE "(actually it'?s|the correct .* is|no,? it should be|it'?s actually)" && MATCH=1

# Group 3: Knowledge gap indicators
[[ $MATCH -eq 0 ]] && echo "$PROMPT_LOWER" | grep -qE "(you should know that|for future reference|remember that)" && MATCH=1

# Group 4: Behavioral corrections
[[ $MATCH -eq 0 ]] && echo "$PROMPT_LOWER" | grep -qE "(don'?t do that|never do that|always .* instead|stop doing)" && MATCH=1

# Group 5: Missing information
[[ $MATCH -eq 0 ]] && echo "$PROMPT_LOWER" | grep -qE "(you'?re missing|you forgot|you didn'?t account for|you overlooked)" && MATCH=1

[[ $MATCH -eq 0 ]] && exit 0

# --- Cooldown: 60 seconds ---
if ! hook_timed_dedup "correction" 60; then
  exit 0
fi

# --- Inject additionalContext ---
cat <<'CONTEXT'
{"additionalContext": "CORRECTION DETECTED: The user appears to be correcting your behavior or knowledge.\n\n1. UPDATE FACTS CACHE: Add the corrected knowledge to notes/<username>/facts.md if it's a reusable cross-session fact (conventions, toolchain details, integration gotchas). Keep facts.md under 80 lines.\n\n2. ASSESS AGENT FILE PROMOTION: Does this correction reveal a gap in an agent file (CLAUDE.md or agents/*.md)?\n\n- If YES: After completing current task, draft the change on this session branch. Log it in notes/agent-changelog.md.\n\n- If NO (one-off mistake, context issue): Update facts.md if useful, move on.\n\nDo NOT interrupt your current work to make the change."}
CONTEXT
