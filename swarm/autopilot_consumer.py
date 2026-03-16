"""AutoPilot Swarm Consumer — adapter for external AutoPilot integration.

Provides a high-level interface for AutoPilot systems to:
- Submit task batches from an AutoPilot plan
- Poll for completed results
- Map AutoPilot task statuses to swarm statuses

This is a consumer interface only. The actual AutoPilot orchestration
logic lives in the AutoPilot repo (see Issue #3).
"""

import json
import time
from dataclasses import dataclass
from typing import Any

from swarm.coordinator import Coordinator, WorkItem, WorkItemStatus


@dataclass
class AutoPilotTask:
    """A task submitted by an AutoPilot plan."""
    name: str
    description: str
    repo: str
    risk_level: str = "medium"
    priority: float = 5.0
    config: dict[str, Any] | None = None


class AutoPilotConsumer:
    """Adapter between AutoPilot plans and the swarm work queue."""

    AGENT_NAME = "autopilot"
    AGENT_ROLE = "orchestrator"

    def __init__(self, coordinator: Coordinator, budget: float = 100.0):
        self.coordinator = coordinator
        self.agent_id = coordinator.register_agent(
            self.AGENT_NAME, self.AGENT_ROLE, budget
        )
        self._task_map: dict[str, str] = {}  # autopilot task name → work item ID

    def submit_plan(self, tasks: list[AutoPilotTask]) -> dict[str, str]:
        """Submit a batch of AutoPilot tasks to the swarm queue.

        Returns mapping of task name → work item ID.
        """
        for task in tasks:
            item_id = self.coordinator.submit_work(
                title=f"[autopilot] {task.name}",
                description=task.description,
                created_by=self.agent_id,
                priority=task.priority,
                metadata={
                    "source": "autopilot",
                    "repo": task.repo,
                    "risk_level": task.risk_level,
                    "config": task.config or {},
                },
            )
            self._task_map[task.name] = item_id

        # Post plan summary to message board
        self.coordinator.post_message(
            channel="autopilot",
            author=self.agent_id,
            content=json.dumps({
                "event": "plan_submitted",
                "task_count": len(tasks),
                "tasks": [t.name for t in tasks],
            }),
        )

        return dict(self._task_map)

    def poll_results(self) -> dict[str, dict[str, Any]]:
        """Poll for results of submitted tasks.

        Returns dict of task name → {status, result, ...} for all finished tasks.
        """
        results = {}
        for name, item_id in self._task_map.items():
            item = self.coordinator.get_work_item(item_id)
            if item and item.status in (WorkItemStatus.COMPLETED, WorkItemStatus.FAILED):
                results[name] = {
                    "status": item.status.value,
                    "result": item.result,
                    "completed_at": item.completed_at,
                    "risk_level": item.metadata.get("risk_level", "medium"),
                }
        return results

    def pending_count(self) -> int:
        """Count tasks still pending or claimed."""
        count = 0
        for item_id in self._task_map.values():
            item = self.coordinator.get_work_item(item_id)
            if item and item.status in (WorkItemStatus.PENDING, WorkItemStatus.CLAIMED):
                count += 1
        return count

    def cancel_pending(self) -> int:
        """Withdraw all pending (unclaimed) tasks. Returns count withdrawn."""
        withdrawn = 0
        for item_id in self._task_map.values():
            if self.coordinator.withdraw_work(item_id, self.agent_id):
                withdrawn += 1
        return withdrawn
