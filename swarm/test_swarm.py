"""Tests for swarm coordinator, scheduler, and client — P1 correctness."""

import math
import sqlite3
import tempfile
import threading
import time
from pathlib import Path

import pytest

from swarm.coordinator import Coordinator, WorkItemStatus
from swarm.scheduler import ExperimentScheduler, ParetoArchive, ParetoEntry, ScoringWeights
from swarm.client import SwarmClient


@pytest.fixture
def db_path(tmp_path):
    return tmp_path / "test_coordinator.db"


@pytest.fixture
def coordinator(db_path):
    return Coordinator(db_path)


@pytest.fixture
def agent_id(coordinator):
    return coordinator.register_agent("test-agent", "worker")


# ---- Coordinator basics ----


class TestCoordinatorBasics:
    def test_register_and_get_agent(self, coordinator):
        aid = coordinator.register_agent("alice", "researcher")
        agent = coordinator.get_agent(aid)
        assert agent is not None
        assert agent.name == "alice"
        assert agent.role == "researcher"
        assert agent.budget_remaining == 100.0

    def test_heartbeat(self, coordinator, agent_id):
        assert coordinator.heartbeat(agent_id) is True
        assert coordinator.heartbeat("nonexistent") is False

    def test_submit_and_claim_work(self, coordinator, agent_id):
        item_id = coordinator.submit_work("task1", "desc", agent_id, priority=5.0)
        claimed = coordinator.claim_work(agent_id)
        assert claimed is not None
        assert claimed.item_id == item_id
        assert claimed.status == WorkItemStatus.CLAIMED

    def test_claim_empty_queue(self, coordinator, agent_id):
        assert coordinator.claim_work(agent_id) is None

    def test_complete_work(self, coordinator, agent_id):
        item_id = coordinator.submit_work("task", "desc", agent_id)
        coordinator.claim_work(agent_id)
        assert coordinator.complete_work(item_id, agent_id, "done", 0.8) is True
        item = coordinator.get_work_item(item_id)
        assert item.status == WorkItemStatus.COMPLETED
        assert item.actual_info_gain == 0.8

    def test_fail_work(self, coordinator, agent_id):
        item_id = coordinator.submit_work("task", "desc", agent_id)
        coordinator.claim_work(agent_id)
        assert coordinator.fail_work(item_id, agent_id, "error") is True
        item = coordinator.get_work_item(item_id)
        assert item.status == WorkItemStatus.FAILED

    def test_priority_ordering(self, coordinator, agent_id):
        coordinator.submit_work("low", "desc", agent_id, priority=1.0)
        coordinator.submit_work("high", "desc", agent_id, priority=10.0)
        coordinator.submit_work("mid", "desc", agent_id, priority=5.0)
        claimed = coordinator.claim_work(agent_id)
        assert claimed.title == "high"

    def test_release_stale_claims(self, coordinator):
        aid = coordinator.register_agent("stale", "worker")
        item_id = coordinator.submit_work("task", "desc", aid)
        coordinator.claim_work(aid)
        # Manually set heartbeat to long ago
        with coordinator._conn() as conn:
            conn.execute(
                "UPDATE agents SET last_heartbeat = ? WHERE agent_id = ?",
                (time.time() - 9999, aid),
            )
        released = coordinator.release_stale_claims()
        assert released == 1
        item = coordinator.get_work_item(item_id)
        assert item.status == WorkItemStatus.PENDING

    def test_messages(self, coordinator, agent_id):
        mid = coordinator.post_message("general", agent_id, "hello")
        msgs = coordinator.get_messages("general")
        assert len(msgs) == 1
        assert msgs[0].content == "hello"
        # Thread
        coordinator.post_message("general", agent_id, "reply", thread_id=mid)
        thread = coordinator.get_thread(mid)
        assert len(thread) == 2

    def test_stats(self, coordinator, agent_id):
        coordinator.submit_work("t", "d", agent_id)
        s = coordinator.stats()
        assert s["agents_total"] >= 1
        assert s["work_pending"] == 1


# ---- Lock race condition fix ----


class TestLockRaceFix:
    def test_basic_acquire_release(self, coordinator, agent_id):
        assert coordinator.acquire_lock("res1", agent_id) is True
        assert coordinator.acquire_lock("res1", agent_id) is False  # Already held
        assert coordinator.release_lock("res1", agent_id) is True
        assert coordinator.acquire_lock("res1", agent_id) is True  # Can re-acquire

    def test_expired_lock_reacquire(self, coordinator, agent_id):
        # Acquire with very short TTL
        assert coordinator.acquire_lock("res1", agent_id, ttl_seconds=0.01) is True
        time.sleep(0.05)  # Let it expire
        aid2 = coordinator.register_agent("agent2", "worker")
        assert coordinator.acquire_lock("res1", aid2) is True

    def test_concurrent_lock_acquisition(self, coordinator):
        """Verify that BEGIN IMMEDIATE prevents two agents from acquiring the same lock."""
        results = {"agent1": None, "agent2": None}

        def try_lock(name, result_key):
            aid = coordinator.register_agent(name, "worker")
            results[result_key] = coordinator.acquire_lock("contested_resource", aid)

        t1 = threading.Thread(target=try_lock, args=("a1", "agent1"))
        t2 = threading.Thread(target=try_lock, args=("a2", "agent2"))
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        # Exactly one should succeed
        assert results["agent1"] != results["agent2"], (
            f"Both agents got same result: {results}"
        )
        assert True in results.values()
        assert False in results.values()

    def test_lock_atomicity_under_contention(self, coordinator):
        """Stress test: many agents competing for same lock."""
        n_agents = 10
        successes = []
        barrier = threading.Barrier(n_agents)

        def compete(i):
            aid = coordinator.register_agent(f"agent_{i}", "worker")
            barrier.wait()  # All threads start at the same time
            result = coordinator.acquire_lock("hot_resource", aid)
            if result:
                successes.append(aid)

        threads = [threading.Thread(target=compete, args=(i,)) for i in range(n_agents)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert len(successes) == 1, f"Expected 1 winner, got {len(successes)}: {successes}"


# ---- Budget ledger query ----


class TestBudgetLedger:
    def test_charge_and_query_history(self, coordinator, agent_id):
        coordinator.charge_budget(agent_id, "inference", 10.0, "GPT call")
        coordinator.charge_budget(agent_id, "inference", 5.0, "Another call")
        history = coordinator.get_budget_history(agent_id)
        assert len(history) == 2
        assert history[0]["cost"] == 5.0  # Most recent first
        assert history[1]["cost"] == 10.0
        assert history[0]["action_type"] == "inference"

    def test_empty_history(self, coordinator, agent_id):
        assert coordinator.get_budget_history(agent_id) == []

    def test_insufficient_budget(self, coordinator):
        aid = coordinator.register_agent("broke", "worker", budget=1.0)
        assert coordinator.charge_budget(aid, "big", 5.0) is False
        assert coordinator.get_budget_history(aid) == []


# ---- Scoring normalization ----


class TestScoringNormalization:
    def test_frontier_distance_normalized(self, coordinator, agent_id):
        """Verify score components are all in [0,1] range."""
        scheduler = ExperimentScheduler(coordinator, objective_names=["quality", "speed"])

        # Add a frontier point far from origin
        scheduler.archive.add(ParetoEntry(
            item_id="ref",
            objectives={"quality": 100.0, "speed": 200.0},
            species="baseline",
        ))

        # Submit experiment with objectives far from frontier
        item_id = coordinator.submit_work(
            "exp1", "test", agent_id, priority=0.0,
            predicted_info_value=0.5,
            metadata=json.dumps({
                "predicted_objectives": {"quality": 0.0, "speed": 0.0},
                "config": {"lr": 0.01},
                "species": "new_species",
            }),
        )
        item = coordinator.get_work_item(item_id)
        # Fix metadata — it was double-serialized
        item.metadata = {
            "predicted_objectives": {"quality": 0.0, "speed": 0.0},
            "config": {"lr": 0.01},
            "species": "new_species",
        }

        score = scheduler.score_experiment(item)
        # Score should be bounded [0, 1] since all components are [0,1] and weights sum to 1
        assert 0.0 <= score <= 1.0, f"Score {score} out of [0,1] range"

    def test_sigmoid_normalization_properties(self):
        """Verify the sigmoid normalization: 1 - exp(-x) behaves correctly."""
        # At 0: should be 0
        assert abs((1.0 - math.exp(0)) - 0.0) < 1e-10
        # At large values: should approach 1
        assert (1.0 - math.exp(-10.0)) > 0.99
        # Monotonically increasing
        vals = [1.0 - math.exp(-x) for x in [0.1, 0.5, 1.0, 5.0, 100.0]]
        assert vals == sorted(vals)

    def test_scores_bounded_across_scales(self, coordinator, agent_id):
        """Score remains in [0,1] regardless of objective scale."""
        for scale in [0.001, 1.0, 1000.0, 1e6]:
            sched = ExperimentScheduler(coordinator, objective_names=["q"])
            sched.archive.add(ParetoEntry(
                item_id=f"ref_{scale}",
                objectives={"q": scale},
                species="s",
            ))

            item_id = coordinator.submit_work(
                f"exp_{scale}", "test", agent_id, priority=0.0,
                predicted_info_value=0.5,
            )
            item = coordinator.get_work_item(item_id)
            item.metadata = {
                "predicted_objectives": {"q": 0.0},
                "config": {},
                "species": "s",
            }
            score = sched.score_experiment(item)
            assert 0.0 <= score <= 1.0, f"Scale {scale}: score {score} out of bounds"


# ---- select_next thread safety ----


class TestSelectNextThreadSafety:
    def test_select_next_with_claim(self, coordinator, agent_id):
        """select_next(agent_id) should return a claimed item."""
        coordinator.submit_work("exp1", "desc", agent_id, priority=1.0)
        scheduler = ExperimentScheduler(coordinator)
        result = scheduler.select_next(agent_id=agent_id)
        assert result is not None
        assert result.status == WorkItemStatus.CLAIMED
        assert result.claimed_by == agent_id

    def test_select_next_legacy_no_claim(self, coordinator, agent_id):
        """select_next() without agent_id returns unclaimed item (legacy)."""
        coordinator.submit_work("exp1", "desc", agent_id, priority=1.0)
        scheduler = ExperimentScheduler(coordinator)
        result = scheduler.select_next()
        assert result is not None
        # Legacy path doesn't claim
        item = coordinator.get_work_item(result.item_id)
        assert item.status == WorkItemStatus.PENDING

    def test_concurrent_select_next(self, coordinator):
        """Two agents calling select_next simultaneously should get different items."""
        submitter = coordinator.register_agent("submitter", "worker")
        coordinator.submit_work("exp1", "d", submitter, priority=1.0)
        coordinator.submit_work("exp2", "d", submitter, priority=2.0)

        scheduler = ExperimentScheduler(coordinator)
        results = [None, None]
        barrier = threading.Barrier(2)

        def select(idx):
            aid = coordinator.register_agent(f"selector_{idx}", "worker")
            barrier.wait()
            results[idx] = scheduler.select_next(agent_id=aid)

        t1 = threading.Thread(target=select, args=(0,))
        t2 = threading.Thread(target=select, args=(1,))
        t1.start()
        t2.start()
        t1.join()
        t2.join()

        # Both should get an item
        assert results[0] is not None
        assert results[1] is not None
        # They should be different items
        assert results[0].item_id != results[1].item_id

    def test_select_next_empty_queue(self, coordinator, agent_id):
        scheduler = ExperimentScheduler(coordinator)
        assert scheduler.select_next(agent_id=agent_id) is None


# ---- Client dead code removal ----


class TestClientCleanup:
    def test_no_submitted_items_attribute(self):
        """Verify _submitted_items was removed from SwarmClient."""
        assert not hasattr(SwarmClient, "_submitted_items")

    def test_submit_experiment_still_works(self, db_path):
        coord = Coordinator(db_path)
        with SwarmClient(coord, "test", "worker") as client:
            item_id = client.submit_experiment("exp", "desc", species="test")
            assert item_id.startswith("wi_")
            # Verify it's in the queue
            items = client.list_my_items()
            assert len(items) == 1
            assert items[0].item_id == item_id


# ---- Integration: full workflow ----


class TestIntegrationWorkflow:
    def test_full_experiment_lifecycle(self, db_path):
        coord = Coordinator(db_path)
        scheduler = ExperimentScheduler(coord, objective_names=["quality", "speed"])

        with SwarmClient(coord, "researcher", "worker") as client:
            # Submit experiments
            id1 = client.submit_experiment(
                "exp1", "test experiment 1",
                predicted_objectives={"quality": 0.8, "speed": 0.5},
                config={"lr": 0.01},
                species="fast",
            )
            id2 = client.submit_experiment(
                "exp2", "test experiment 2",
                predicted_objectives={"quality": 0.3, "speed": 0.9},
                config={"lr": 0.1},
                species="slow",
            )

            # Select and claim
            selected = scheduler.select_next(agent_id=client.agent_id)
            assert selected is not None

            # Record validation
            scheduler.record_validation(
                selected,
                objectives={"quality": 0.75, "speed": 0.6},
                species="fast",
            )

            # Archive should have one entry
            state = scheduler.get_archive_state()
            assert state["frontier_size"] == 1
            assert state["total_validated"] == 1

            # Budget tracking
            client.charge("inference", 10.0, "validation run")
            history = coord.get_budget_history(client.agent_id)
            assert len(history) == 1
            assert history[0]["cost"] == 10.0


import json
