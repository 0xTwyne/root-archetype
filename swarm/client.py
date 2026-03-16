"""
Swarm Client — Thin library for agents to interact with the coordinator.

Each agent creates a SwarmClient, registers itself, and uses it to:
- Claim and complete work items
- Post and read messages
- Acquire and release resource locks
- Submit experiments with predicted information value
- Receive re-score notifications after validations
"""

import json
import time
import threading
from dataclasses import asdict
from pathlib import Path
from typing import Any, Callable, Optional

from swarm.constants import (
    DEFAULT_AGENT_BUDGET,
    DEFAULT_HEARTBEAT_INTERVAL,
    DEFAULT_MESSAGE_LIMIT,
    MAX_PENDING_SCAN,
)
from swarm.coordinator import (
    Coordinator, WorkItem, WorkItemStatus, Message, ResourceLock, Agent,
)


class SwarmClient:
    """Client interface for a single swarm agent."""

    def __init__(
        self,
        coordinator: Coordinator,
        name: str,
        role: str,
        budget: float = DEFAULT_AGENT_BUDGET,
        heartbeat_interval: float = DEFAULT_HEARTBEAT_INTERVAL,
    ):
        self.coordinator = coordinator
        self.name = name
        self.role = role
        self.agent_id = coordinator.register_agent(name, role, budget)
        self._heartbeat_interval = heartbeat_interval
        self._heartbeat_thread: threading.Thread | None = None
        self._running = False
        self._held_locks: set[str] = set()

    # ---- Lifecycle ----

    def start(self):
        """Start the heartbeat thread."""
        self._running = True
        self._heartbeat_thread = threading.Thread(
            target=self._heartbeat_loop, daemon=True
        )
        self._heartbeat_thread.start()

    def stop(self):
        """Stop the heartbeat and release all held locks."""
        self._running = False
        if self._heartbeat_thread:
            self._heartbeat_thread.join(timeout=5)
        # Release all locks
        for resource_id in list(self._held_locks):
            self.release_lock(resource_id)

    def _heartbeat_loop(self):
        """Background heartbeat to keep agent registration alive."""
        while self._running:
            self.coordinator.heartbeat(self.agent_id)
            time.sleep(self._heartbeat_interval)

    # ---- Work Queue ----

    def submit_experiment(
        self,
        title: str,
        description: str,
        predicted_info_value: float = 0.5,
        predicted_objectives: dict[str, float] | None = None,
        config: dict[str, Any] | None = None,
        species: str = "",
        priority: float = 0.0,
        parent_item_id: str | None = None,
    ) -> str:
        """Submit an experiment to the work queue.

        Args:
            title: Short experiment description
            description: Detailed experiment specification
            predicted_info_value: Agent's estimate of information value (0-1)
            predicted_objectives: Predicted outcome metrics
            config: Experiment configuration dict
            species: Species identifier (seeder, numeric_swarm, etc.)
            priority: Initial priority (will be re-scored by scheduler)
            parent_item_id: Parent experiment for genealogy tracking
        """
        metadata = {
            "predicted_objectives": predicted_objectives or {},
            "config": config or {},
            "species": species,
        }
        item_id = self.coordinator.submit_work(
            title=title,
            description=description,
            created_by=self.agent_id,
            priority=priority,
            predicted_info_value=predicted_info_value,
            parent_item_id=parent_item_id,
            metadata=metadata,
        )
        return item_id

    def claim_work(self) -> WorkItem | None:
        """Claim the highest-priority available work item."""
        return self.coordinator.claim_work(self.agent_id)

    def complete_work(
        self, item_id: str, result: str = "", actual_info_gain: float | None = None
    ) -> bool:
        """Mark claimed work as completed."""
        return self.coordinator.complete_work(
            item_id, self.agent_id, result, actual_info_gain
        )

    def fail_work(self, item_id: str, result: str = "") -> bool:
        """Mark claimed work as failed."""
        return self.coordinator.fail_work(item_id, self.agent_id, result)

    def withdraw_experiment(self, item_id: str) -> bool:
        """Withdraw a pending experiment (e.g., after re-scoring makes it redundant)."""
        return self.coordinator.withdraw_work(item_id, self.agent_id)

    def update_experiment_priority(self, item_id: str, new_priority: float) -> bool:
        """Update priority of a submitted experiment after re-scoring."""
        return self.coordinator.update_priority(item_id, new_priority)

    def list_my_items(self) -> list[WorkItem]:
        """List work items created by this agent."""
        all_items = self.coordinator.list_work(limit=MAX_PENDING_SCAN)
        return [item for item in all_items if item.created_by == self.agent_id]

    # ---- Message Board ----

    def post(
        self, channel: str, content: str, thread_id: str | None = None,
        metadata: dict | None = None,
    ) -> str:
        """Post a message to a channel."""
        return self.coordinator.post_message(
            channel, self.agent_id, content, thread_id, metadata
        )

    def read_messages(
        self, channel: str, since: float = 0, limit: int = DEFAULT_MESSAGE_LIMIT
    ) -> list[Message]:
        """Read messages from a channel."""
        return self.coordinator.get_messages(channel, since, limit)

    def read_thread(self, thread_id: str) -> list[Message]:
        """Read a message thread."""
        return self.coordinator.get_thread(thread_id)

    # ---- Resource Locks ----

    def acquire_lock(
        self, resource_id: str, ttl_seconds: float | None = None
    ) -> bool:
        """Acquire a resource lock."""
        acquired = self.coordinator.acquire_lock(
            resource_id, self.agent_id, ttl_seconds
        )
        if acquired:
            self._held_locks.add(resource_id)
        return acquired

    def release_lock(self, resource_id: str) -> bool:
        """Release a resource lock."""
        released = self.coordinator.release_lock(resource_id, self.agent_id)
        self._held_locks.discard(resource_id)
        return released

    def check_lock(self, resource_id: str) -> ResourceLock | None:
        """Check if a resource is locked."""
        return self.coordinator.check_lock(resource_id)

    # ---- Budget ----

    def charge(self, action_type: str, cost: float, description: str = "") -> bool:
        """Charge this agent's budget."""
        return self.coordinator.charge_budget(
            self.agent_id, action_type, cost, description
        )

    @property
    def budget(self) -> float:
        """Current remaining budget."""
        agent = self.coordinator.get_agent(self.agent_id)
        return agent.budget_remaining if agent else 0.0

    # ---- Context ----

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *args):
        self.stop()

    def __repr__(self):
        return f"SwarmClient(name={self.name!r}, role={self.role!r}, id={self.agent_id!r})"
