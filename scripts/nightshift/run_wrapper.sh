#!/bin/bash
set -euo pipefail

# Nightshift run wrapper — autonomous overnight task scheduler
# Usage: run_wrapper.sh [--swarm] [--workers N] [--dry-run]

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/../.." && pwd)")"

# --- Configuration ---
NIGHTSHIFT_DISABLED="${NIGHTSHIFT_DISABLED:-0}"
NIGHTSHIFT_MAX_WORKERS="${NIGHTSHIFT_MAX_WORKERS:-2}"
NIGHTSHIFT_CONFIG="${ROOT_DIR}/nightshift.yaml"
LOG_DIR="${ROOT_DIR}/logs/nightshift"
WORKTREE_BASE="${ROOT_DIR}-nightshift"

SWARM_MODE=false
DRY_RUN=false
WORKERS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --swarm) SWARM_MODE=true; shift ;;
        --workers) WORKERS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) shift ;;
    esac
done

# --- Kill switch ---
if [[ "$NIGHTSHIFT_DISABLED" == "1" ]] || [[ -f "${ROOT_DIR}/.nightshift_disabled" ]]; then
    echo "Nightshift is disabled. Set NIGHTSHIFT_DISABLED=0 or remove .nightshift_disabled"
    exit 0
fi

# --- Setup logging ---
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/$(date +%Y-%m-%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Nightshift Run: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Mode: $([ "$SWARM_MODE" = true ] && echo "swarm (${WORKERS} workers)" || echo "sequential")"

# --- Source logging ---
source "${ROOT_DIR}/scripts/utils/agent_log.sh"
agent_session_start "Nightshift run ($([ "$SWARM_MODE" = true ] && echo "swarm" || echo "sequential"))"

# --- Check compute load ---
INFERENCE_ACTIVE=false
NIGHTSHIFT_HEAVY_PROCESS="${NIGHTSHIFT_HEAVY_PROCESS:-}"
if [[ -n "$NIGHTSHIFT_HEAVY_PROCESS" ]] && command -v pgrep &>/dev/null; then
    HEAVY_RSS=0
    while read -r pid; do
        RSS=$(awk '/^VmRSS/ {print int($2/1048576)}' "/proc/$pid/status" 2>/dev/null || echo 0)
        HEAVY_RSS=$((HEAVY_RSS + RSS))
    done < <(pgrep -f "$NIGHTSHIFT_HEAVY_PROCESS" 2>/dev/null || true)

    THRESHOLD_GB="${NIGHTSHIFT_INFERENCE_THRESHOLD_GB:-50}"
    if [[ $HEAVY_RSS -ge $THRESHOLD_GB ]]; then
        INFERENCE_ACTIVE=true
        echo "Heavy compute active (${HEAVY_RSS}GB RSS >= ${THRESHOLD_GB}GB threshold)"
        echo "Running analysis-only tasks."
    fi
fi

# --- Load task config ---
if [[ ! -f "$NIGHTSHIFT_CONFIG" ]]; then
    echo "No nightshift.yaml found. Nothing to do."
    exit 0
fi

# --- Worktree setup ---
setup_worktree() {
    local name="$1"
    local wt_path="${WORKTREE_BASE}-${name}"

    if [[ -d "$wt_path" ]]; then
        git -C "$wt_path" checkout main 2>/dev/null || true
        git -C "$wt_path" pull --rebase 2>/dev/null || true
    else
        git worktree add "$wt_path" -b "nightshift-${name}-$(date +%Y%m%d)" main 2>/dev/null || {
            # Branch might exist, just checkout
            git worktree add "$wt_path" main 2>/dev/null || true
        }
    fi
    echo "$wt_path"
}

# --- Sequential mode (backward compatible) ---
run_sequential() {
    echo "Running in sequential mode..."
    local wt_path
    wt_path=$(setup_worktree "main")

    agent_task_start "Sequential nightshift" "Processing tasks one at a time"

    # Parse tasks from yaml, ordered by priority descending
    local task_count
    task_count=$(yq '.tasks | length' "$NIGHTSHIFT_CONFIG")
    echo "Found ${task_count} tasks in nightshift.yaml"

    for i in $(seq 0 $((task_count - 1))); do
        local name description risk analysis_only
        name=$(yq ".tasks[$i].name" "$NIGHTSHIFT_CONFIG")
        description=$(yq ".tasks[$i].description" "$NIGHTSHIFT_CONFIG")
        risk=$(yq ".tasks[$i].risk_level" "$NIGHTSHIFT_CONFIG")
        analysis_only=$(yq ".tasks[$i].analysis_only" "$NIGHTSHIFT_CONFIG")

        # Skip non-analysis tasks when inference is active
        if [[ "$INFERENCE_ACTIVE" == "true" && "$analysis_only" != "true" ]]; then
            echo "  SKIP: ${name} (inference active, not analysis-only)"
            continue
        fi

        echo ""
        echo "--- Task: ${name} [${risk}] ---"
        echo "  ${description}"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would execute in ${wt_path}"
            continue
        fi

        agent_task_start "nightshift:${name}" "${description}"

        # Execute task as a Claude Code session in the worktree
        local task_result=0
        if command -v claude &>/dev/null; then
            claude --worktree "$wt_path" \
                --message "Run nightshift task '${name}': ${description}. Risk level: ${risk}. Report findings in a structured format." \
                --max-turns 10 \
                --output-format json \
                > "${LOG_DIR}/${name}-$(date +%Y%m%d).json" 2>&1 || task_result=$?
        else
            echo "  WARN: claude CLI not available, skipping execution"
            task_result=1
        fi

        if [[ $task_result -eq 0 ]]; then
            echo "  DONE: ${name}"
            agent_task_end "nightshift:${name}" "success"
        else
            echo "  FAIL: ${name} (exit=${task_result})"
            agent_task_end "nightshift:${name}" "failure"
        fi
    done

    agent_task_end "Sequential nightshift" "success"
}

# --- Swarm mode ---
run_swarm() {
    echo "Running in swarm mode with ${WORKERS} workers..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would start coordinator and ${WORKERS} workers"
        return
    fi

    # Initialize coordinator
    python3 -c "
import sys
sys.path.insert(0, '${ROOT_DIR}')
from swarm.coordinator import Coordinator

coord = Coordinator('${ROOT_DIR}/swarm/coordinator.db')

# Load tasks from config and submit as work items
import yaml
with open('${NIGHTSHIFT_CONFIG}') as f:
    config = yaml.safe_load(f)

inference_active = ${INFERENCE_ACTIVE:+True} or False

for task in config.get('tasks', []):
    if inference_active and not task.get('analysis_only', False):
        continue
    coord.submit_work(
        title=task['name'],
        description=task.get('description', ''),
        created_by='nightshift-scheduler',
        priority=float(task.get('priority', 0)),
        metadata={
            'risk_level': task.get('risk_level', 'medium'),
            'analysis_only': task.get('analysis_only', False),
        },
    )
    print(f'  Submitted: {task[\"name\"]} (priority={task[\"priority\"]})')

stats = coord.stats()
print(f'\\nCoordinator: {stats[\"work_pending\"]} tasks pending')
"

    # Launch workers
    WORKER_PIDS=()
    for i in $(seq 1 "$WORKERS"); do
        local wt_path
        wt_path=$(setup_worktree "worker-${i}")
        echo "Worker ${i}: worktree at ${wt_path}"

        if ! command -v claude &>/dev/null; then
            echo "  WARN: claude CLI not available, cannot launch workers"
            break
        fi

        # Each worker claims and executes tasks from the swarm queue
        claude --worktree "$wt_path" \
            --message "You are swarm worker ${i}. Claim tasks from the coordinator queue at ${ROOT_DIR}/swarm/coordinator.db, execute them, and report results. Use /swarm to interact with the coordinator. Stop when no pending tasks remain." \
            --max-turns 30 \
            --output-format json \
            > "${LOG_DIR}/worker-${i}-$(date +%Y%m%d).json" 2>&1 &
        WORKER_PIDS+=($!)
        echo "  PID: ${WORKER_PIDS[-1]}"
    done

    if [[ ${#WORKER_PIDS[@]} -gt 0 ]]; then
        echo ""
        echo "Swarm launched with ${#WORKER_PIDS[@]} workers."
        echo "Waiting for workers to finish..."
        for pid in "${WORKER_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || echo "  Worker PID ${pid} exited with error"
        done
        echo "All workers finished."
    fi

    echo "Monitor: python3 -c \"from swarm import Coordinator; print(Coordinator('${ROOT_DIR}/swarm/coordinator.db').stats())\""
}

# --- Generate consolidated report ---
generate_report() {
    echo ""
    echo "=== Generating Consolidated Report ==="

    python3 -c "
import sys, json
sys.path.insert(0, '${ROOT_DIR}')
from swarm.coordinator import Coordinator, WorkItemStatus

coord = Coordinator('${ROOT_DIR}/swarm/coordinator.db')

completed = coord.list_work(status=WorkItemStatus.COMPLETED, limit=100)
failed = coord.list_work(status=WorkItemStatus.FAILED, limit=100)

# Group by risk level
auto_merged = []
needs_review = []
blocked = []

for item in completed:
    risk = item.metadata.get('risk_level', 'medium')
    if risk == 'low':
        auto_merged.append(item)
    else:
        needs_review.append(item)

for item in failed:
    blocked.append(item)

report = []
report.append('## Nightshift Report')
report.append('')

if auto_merged:
    report.append('### Auto-merged (low-risk)')
    for item in auto_merged:
        report.append(f'- **{item.title}**: {item.result or \"completed\"}')
    report.append('')

if needs_review:
    report.append('### Needs Review')
    for item in needs_review:
        report.append(f'- **{item.title}** [{item.metadata.get(\"risk_level\", \"medium\")}]: {item.result or \"completed\"}')
    report.append('')

if blocked:
    report.append('### Blocked / Failed')
    for item in blocked:
        report.append(f'- **{item.title}**: {item.result or \"unknown failure\"}')
    report.append('')

if not (auto_merged or needs_review or blocked):
    report.append('No tasks completed in this run.')

print('\\n'.join(report))
" > "${ROOT_DIR}/logs/nightshift/report-$(date +%Y%m%d).md"

    echo "Report saved to: logs/nightshift/report-$(date +%Y%m%d).md"
}

# --- Prune old logs ---
prune_logs() {
    find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true
    find "$LOG_DIR" -name "report-*.md" -mtime +30 -delete 2>/dev/null || true
}

# --- Main ---
if [[ "$SWARM_MODE" == "true" ]]; then
    run_swarm
else
    run_sequential
fi

if [[ "$SWARM_MODE" == "true" && "$DRY_RUN" != "true" ]]; then
    generate_report
fi

prune_logs
agent_session_end "Nightshift complete"
echo "=== Nightshift complete: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
