#!/bin/bash
set -euo pipefail

# Agent audit log analyzer
# Usage: ./agent_log_analyze.sh [--summary|--errors|--sessions|--timeline N|--loops]


# CR-safe jq (Windows jq emits CRLF; the CR survives $( ) and corrupts values).
_CRSAFE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
while [[ "$_CRSAFE" != "/" && ! -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]]; do
  _CRSAFE="$(dirname "$_CRSAFE")"
done
[[ -f "$_CRSAFE/scripts/lib/cr-safe-jq.sh" ]] && source "$_CRSAFE/scripts/lib/cr-safe-jq.sh"

LOG_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")/logs"
LOG_FILE="${LOG_DIR}/agent_audit.log"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ ! -f "$LOG_FILE" ]]; then
    echo "No audit log found at ${LOG_FILE}"
    exit 0
fi

case "${1:---summary}" in
    --summary)
        echo -e "${BLUE}=== Agent Audit Summary ===${NC}"
        echo ""
        local_sessions=$(jq -r '.session' "$LOG_FILE" | sort -u | wc -l)
        total_entries=$(wc -l < "$LOG_FILE")
        errors=$(grep -c '"ERROR"' "$LOG_FILE" 2>/dev/null || echo 0)
        warnings=$(grep -c '"WARN"' "$LOG_FILE" 2>/dev/null || echo 0)
        echo "Sessions:  ${local_sessions}"
        echo "Entries:   ${total_entries}"
        echo -e "Errors:    ${RED}${errors}${NC}"
        echo -e "Warnings:  ${YELLOW}${warnings}${NC}"
        echo ""
        echo "Recent activity:"
        tail -5 "$LOG_FILE" | jq -r '"\(.ts) [\(.level)] \(.cat): \(.msg)"'
        ;;
    --errors)
        echo -e "${RED}=== Errors and Warnings ===${NC}"
        grep -E '"(ERROR|WARN)"' "$LOG_FILE" | jq -r '"\(.ts) [\(.level)] \(.msg) | \(.details)"'
        ;;
    --sessions)
        echo -e "${BLUE}=== Sessions ===${NC}"
        jq -r '.session' "$LOG_FILE" | sort -u | while read -r sid; do
            count=$(grep -c "\"${sid}\"" "$LOG_FILE")
            first=$(grep "\"${sid}\"" "$LOG_FILE" | head -1 | jq -r '.ts')
            last=$(grep "\"${sid}\"" "$LOG_FILE" | tail -1 | jq -r '.ts')
            echo "${sid}: ${count} entries (${first} → ${last})"
        done
        ;;
    --timeline)
        N="${2:-20}"
        echo -e "${BLUE}=== Last ${N} entries ===${NC}"
        tail -n "$N" "$LOG_FILE" | jq -r '"\(.ts) [\(.level)] \(.cat): \(.msg)"'
        ;;
    --loops)
        echo -e "${YELLOW}=== Loop Detection ===${NC}"
        echo "Commands repeated 3+ times in same session:"
        jq -r 'select(.cat == "CMD_INTENT") | "\(.session)|\(.msg)"' "$LOG_FILE" | \
            sort | uniq -c | sort -rn | awk '$1 >= 3 {print "  " $1 "x: " $2}'
        ;;
    --commands)
        echo -e "${BLUE}=== Command Frequency ===${NC}"
        jq -r 'select(.cat == "CMD_INTENT") | .msg' "$LOG_FILE" | \
            sort | uniq -c | sort -rn | head -20
        ;;
    --files)
        echo -e "${BLUE}=== File Modifications ===${NC}"
        jq -r 'select(.cat == "FILE_MODIFY") | "\(.ts) \(.msg) \(.details)"' "$LOG_FILE"
        ;;
    *)
        echo "Usage: $0 [--summary|--errors|--sessions|--timeline N|--loops|--commands|--files]"
        ;;
esac
