"""Tests for swarm observability metrics."""

import tempfile
import time
from pathlib import Path

import pytest

from swarm.coordinator import Coordinator
from swarm.metrics import SwarmMetrics


@pytest.fixture
def db_path(tmp_path):
    return tmp_path / "test_metrics.db"


@pytest.fixture
def coordinator(db_path):
    return Coordinator(db_path)


@pytest.fixture
def metrics(db_path, coordinator):
    """Metrics reader — depends on coordinator to ensure tables exist."""
    return SwarmMetrics(db_path)


class TestQueueCounts:
    def test_empty(self, metrics):
        assert metrics.queue_counts() == {}

    def test_counts_by_status(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        coordinator.submit_work("t1", "", a, priority=1)
        coordinator.submit_work("t2", "", a, priority=2)
        coordinator.claim_work(a)
        counts = metrics.queue_counts()
        assert counts["pending"] == 1
        assert counts["claimed"] == 1


class TestWorkLatency:
    def test_empty(self, metrics):
        result = metrics.work_latency()
        assert result["count"] == 0

    def test_latency_computed(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        item_id = coordinator.submit_work("task", "", a, priority=1)
        item = coordinator.claim_work(a)
        coordinator.complete_work(item.item_id, a, "done", actual_info_gain=0.5)

        result = metrics.work_latency()
        assert result["count"] == 1
        assert result["wait_time"]["min"] >= 0
        assert result["exec_time"]["min"] >= 0
        assert result["total_time"]["min"] >= 0

    def test_multiple_items(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        for i in range(5):
            coordinator.submit_work(f"task-{i}", "", a, priority=i)
        for i in range(5):
            item = coordinator.claim_work(a)
            coordinator.complete_work(item.item_id, a, "done")

        result = metrics.work_latency()
        assert result["count"] == 5
        assert result["wait_time"]["p50"] >= 0


class TestBudgetBurnRate:
    def test_empty(self, metrics):
        assert metrics.budget_burn_rate() == []

    def test_burn_rate(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker", budget=100)
        coordinator.charge_budget(a, "inference", 10.0, "test call")
        coordinator.charge_budget(a, "inference", 5.0, "test call 2")
        coordinator.charge_budget(a, "tool_use", 3.0, "test tool")

        result = metrics.budget_burn_rate(window_seconds=3600)
        assert len(result) == 1
        agent = result[0]
        assert agent["total_spend"] == 18.0
        assert agent["budget_remaining"] == 82.0
        assert agent["burn_rate_per_hour"] > 0
        assert agent["by_action_type"]["inference"] == 15.0
        assert agent["by_action_type"]["tool_use"] == 3.0


class TestAgentActivity:
    def test_activity_tracking(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        b = coordinator.register_agent("b", "researcher")
        # a completes 2, b fails 1
        for _ in range(3):
            coordinator.submit_work("task", "", a, priority=1)
        item1 = coordinator.claim_work(a)
        coordinator.complete_work(item1.item_id, a, "done")
        item2 = coordinator.claim_work(a)
        coordinator.complete_work(item2.item_id, a, "done")
        item3 = coordinator.claim_work(b)
        coordinator.fail_work(item3.item_id, b, "error")

        result = metrics.agent_activity()
        by_name = {r["name"]: r for r in result}
        assert by_name["a"]["work_completed"] == 2
        assert by_name["b"]["work_failed"] == 1
        assert by_name["a"]["active"] is True


class TestInfoGainAccuracy:
    def test_empty(self, metrics):
        assert metrics.info_gain_accuracy()["count"] == 0

    def test_accuracy(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        coordinator.submit_work("t1", "", a, priority=1, predicted_info_value=0.8)
        item = coordinator.claim_work(a)
        coordinator.complete_work(item.item_id, a, "done", actual_info_gain=0.6)

        result = metrics.info_gain_accuracy()
        assert result["count"] == 1
        assert result["mean_error"] == -0.2  # actual - predicted


class TestLockStatus:
    def test_empty(self, metrics):
        result = metrics.lock_status()
        assert result["active_locks"] == 0

    def test_active_lock(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        coordinator.acquire_lock("inference", a, ttl_seconds=300)
        result = metrics.lock_status()
        assert result["active_locks"] == 1
        assert result["locks"][0]["resource_id"] == "inference"


class TestSnapshot:
    def test_full_snapshot(self, coordinator, metrics):
        a = coordinator.register_agent("a", "worker")
        coordinator.submit_work("task", "", a, priority=1)
        snap = metrics.snapshot()
        assert "timestamp" in snap
        assert "queue_counts" in snap
        assert "work_latency" in snap
        assert "agent_activity" in snap
        assert "budget_burn_rate" in snap
        assert "info_gain_accuracy" in snap
        assert "lock_status" in snap


class TestAuditTrailIntegration:
    def test_emit_to_log(self, coordinator, metrics, tmp_path):
        a = coordinator.register_agent("a", "worker")
        metrics.emit_to_audit_log(log_dir=tmp_path)
        log_file = tmp_path / "agent_audit.log"
        assert log_file.exists()
        import json
        entry = json.loads(log_file.read_text().strip())
        assert entry["cat"] == "SWARM_METRICS"
        assert entry["level"] == "INFO"
        details = json.loads(entry["details"])
        assert "queue_counts" in details
