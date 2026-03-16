"""
Experiment Scheduler — Information-gain-aware experiment prioritization.

Sits between the swarm and the validation endpoint. Selects which queued
experiment to validate next based on expected information gain about the
Pareto frontier.

Scoring approach: Expected Improvement (EI) over Pareto hypervolume.
- Distance from current frontier (further = more informative)
- Novelty vs already-validated configs (dissimilar = more informative)
- Species diversity (under-explored species get priority)
- Uncertainty (experiments in unexplored regions of objective space)

After each validation, triggers re-scoring of all queued experiments.
"""

import json
import math
import time
from dataclasses import dataclass, field
from typing import Any, Optional

from swarm.constants import MC_HYPERVOLUME_SAMPLES, EPSILON, MAX_PENDING_SCAN
from swarm.coordinator import Coordinator, WorkItem, WorkItemStatus


@dataclass
class ParetoEntry:
    """A point on the Pareto frontier."""
    item_id: str
    objectives: dict[str, float]  # e.g. {"quality": 2.5, "speed": 25.0, "cost": -0.3}
    config: dict[str, Any] = field(default_factory=dict)
    species: str = ""
    timestamp: float = 0.0


@dataclass
class ScoringWeights:
    """Weights for the information gain scoring function."""
    frontier_distance: float = 0.4
    novelty: float = 0.3
    species_diversity: float = 0.2
    uncertainty: float = 0.1


class ParetoArchive:
    """In-memory Pareto archive with hypervolume tracking."""

    def __init__(self, objective_names: list[str], reference_point: dict[str, float] | None = None):
        self.objective_names = objective_names
        self.entries: list[ParetoEntry] = []
        self.reference_point = reference_point or {n: 0.0 for n in objective_names}

    def add(self, entry: ParetoEntry) -> bool:
        """Add entry if it's non-dominated. Returns True if added to frontier."""
        obj = [entry.objectives.get(n, 0.0) for n in self.objective_names]

        # Check if dominated by any existing entry
        for existing in self.entries:
            e_obj = [existing.objectives.get(n, 0.0) for n in self.objective_names]
            if self._dominates(e_obj, obj):
                return False

        # Remove entries dominated by the new one
        self.entries = [
            e for e in self.entries
            if not self._dominates(obj, [e.objectives.get(n, 0.0) for n in self.objective_names])
        ]
        self.entries.append(entry)
        return True

    def _dominates(self, a: list[float], b: list[float]) -> bool:
        """Check if a dominates b (all >=, at least one >)."""
        all_geq = all(ai >= bi for ai, bi in zip(a, b))
        any_gt = any(ai > bi for ai, bi in zip(a, b))
        return all_geq and any_gt

    def frontier_distance(self, objectives: dict[str, float]) -> float:
        """Compute minimum normalized distance from a point to the Pareto frontier."""
        if not self.entries:
            return 1.0  # Maximum distance if frontier is empty

        obj = [objectives.get(n, 0.0) for n in self.objective_names]
        min_dist = float("inf")

        for entry in self.entries:
            e_obj = [entry.objectives.get(n, 0.0) for n in self.objective_names]
            # Euclidean distance in normalized objective space
            dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(obj, e_obj)))
            min_dist = min(min_dist, dist)

        return min_dist

    def hypervolume(self) -> float:
        """Approximate hypervolume indicator (2D exact, >2D Monte Carlo)."""
        if not self.entries:
            return 0.0

        n_obj = len(self.objective_names)
        ref = [self.reference_point.get(n, 0.0) for n in self.objective_names]
        points = [
            [e.objectives.get(n, 0.0) for n in self.objective_names]
            for e in self.entries
        ]

        if n_obj == 2:
            return self._hypervolume_2d(points, ref)
        else:
            return self._hypervolume_mc(points, ref, n_samples=MC_HYPERVOLUME_SAMPLES)

    def _hypervolume_2d(self, points: list[list[float]], ref: list[float]) -> float:
        """Exact 2D hypervolume calculation."""
        # Sort by first objective descending
        pts = sorted(points, key=lambda p: p[0], reverse=True)
        hv = 0.0
        prev_y = ref[1]
        for p in pts:
            if p[0] > ref[0] and p[1] > prev_y:
                hv += (p[0] - ref[0]) * (p[1] - prev_y)
                prev_y = p[1]
        return hv

    def _hypervolume_mc(
        self, points: list[list[float]], ref: list[float], n_samples: int = MC_HYPERVOLUME_SAMPLES
    ) -> float:
        """Monte Carlo hypervolume approximation for >2D."""
        import random
        n_obj = len(ref)

        # Find bounding box
        upper = [max(p[i] for p in points) for i in range(n_obj)]
        lower = ref

        # Volume of bounding box
        box_vol = 1.0
        for i in range(n_obj):
            box_vol *= max(upper[i] - lower[i], EPSILON)

        # Sample random points and check if dominated by any frontier point
        dominated_count = 0
        for _ in range(n_samples):
            sample = [random.uniform(lower[i], upper[i]) for i in range(n_obj)]
            for p in points:
                if all(p[j] >= sample[j] for j in range(n_obj)):
                    dominated_count += 1
                    break

        return box_vol * dominated_count / n_samples


class ExperimentScheduler:
    """Selects highest-information experiments for validation.

    Uses Expected Improvement over Pareto hypervolume as the scoring heuristic.
    """

    def __init__(
        self,
        coordinator: Coordinator,
        objective_names: list[str] | None = None,
        weights: ScoringWeights | None = None,
    ):
        self.coordinator = coordinator
        self.objective_names = objective_names or ["quality", "speed"]
        self.weights = weights or ScoringWeights()
        self.archive = ParetoArchive(self.objective_names)
        self._species_counts: dict[str, int] = {}
        self._validated_configs: list[dict] = []

    def score_experiment(self, item: WorkItem) -> float:
        """Score a work item by expected information gain.

        Components:
        1. Frontier distance — how far the predicted outcome is from the frontier
        2. Novelty — how different this config is from already-validated ones
        3. Species diversity — bonus for under-explored species
        4. Uncertainty — bonus for unexplored regions
        """
        meta = item.metadata
        predicted = meta.get("predicted_objectives", {})
        config = meta.get("config", {})
        species = meta.get("species", "unknown")

        # 1. Frontier distance (normalized to [0,1] via sigmoid)
        if predicted:
            raw_dist = self.archive.frontier_distance(predicted)
            # Sigmoid normalization: maps arbitrary magnitude to (0, 1]
            # k controls steepness; calibrated so dist=1.0 → ~0.73
            dist = 1.0 - math.exp(-raw_dist)
        else:
            dist = 0.5  # Default if no prediction

        # 2. Novelty vs validated configs
        novelty = self._config_novelty(config)

        # 3. Species diversity
        total_validated = sum(self._species_counts.values()) or 1
        species_count = self._species_counts.get(species, 0)
        diversity = 1.0 - (species_count / total_validated)

        # 4. Uncertainty (use predicted_info_value as a proxy)
        uncertainty = min(item.predicted_info_value, 1.0)

        # Weighted sum
        score = (
            self.weights.frontier_distance * dist
            + self.weights.novelty * novelty
            + self.weights.species_diversity * diversity
            + self.weights.uncertainty * uncertainty
        )
        return score

    def _config_novelty(self, config: dict) -> float:
        """Compute novelty of a config relative to already-validated configs."""
        if not self._validated_configs or not config:
            return 1.0

        # Simple Jaccard-style dissimilarity
        config_keys = set(f"{k}={v}" for k, v in config.items())
        min_similarity = 1.0
        for validated in self._validated_configs:
            val_keys = set(f"{k}={v}" for k, v in validated.items())
            if not config_keys and not val_keys:
                continue
            intersection = len(config_keys & val_keys)
            union = len(config_keys | val_keys) or 1
            similarity = intersection / union
            min_similarity = min(min_similarity, similarity)
        return 1.0 - min_similarity

    def select_next(self, agent_id: str | None = None) -> WorkItem | None:
        """Select and claim the highest-information pending experiment.

        Re-scores all pending items, then atomically claims the best one
        via the coordinator to prevent two callers selecting the same item.

        Args:
            agent_id: Agent to claim on behalf of. If None, selects without claiming
                      (legacy behavior, not thread-safe).
        """
        pending = self.coordinator.list_work(status=WorkItemStatus.PENDING, limit=MAX_PENDING_SCAN)
        if not pending:
            return None

        # Score and update priorities for all pending items
        scored: list[tuple[float, WorkItem]] = []
        for item in pending:
            score = self.score_experiment(item)
            self.coordinator.update_priority(item.item_id, score)
            scored.append((score, item))

        scored.sort(key=lambda x: x[0], reverse=True)

        if agent_id is None:
            # Legacy non-atomic path
            return scored[0][1] if scored else None

        # Try to claim top-scored items in order (another agent may have claimed the top one)
        for _score, item in scored:
            claimed = self.coordinator.claim_work(agent_id)
            if claimed:
                return claimed

        return None

    def record_validation(
        self,
        item: WorkItem,
        objectives: dict[str, float],
        config: dict | None = None,
        species: str = "",
    ):
        """Record a validation result and update the archive.

        After recording, triggers re-scoring of all pending experiments.
        """
        entry = ParetoEntry(
            item_id=item.item_id,
            objectives=objectives,
            config=config or item.metadata.get("config", {}),
            species=species or item.metadata.get("species", "unknown"),
            timestamp=time.time(),
        )

        is_frontier = self.archive.add(entry)
        self._validated_configs.append(entry.config)

        # Update species counts
        s = entry.species
        self._species_counts[s] = self._species_counts.get(s, 0) + 1

        # Compute actual information gain (hypervolume change)
        # This is approximate — we'd need to track hypervolume before/after
        actual_gain = 1.0 if is_frontier else 0.1

        # Update the work item with actual gain
        self.coordinator.complete_work(
            item.item_id,
            item.claimed_by or "",
            result=json.dumps({"objectives": objectives, "is_frontier": is_frontier}),
            actual_info_gain=actual_gain,
        )

        # Post result to message board
        self.coordinator.post_message(
            channel="validations",
            author="scheduler",
            content=json.dumps({
                "item_id": item.item_id,
                "title": item.title,
                "objectives": objectives,
                "is_frontier": is_frontier,
                "species": entry.species,
            }),
        )

        # Re-score all pending experiments (the information landscape shifted)
        self._rescore_pending()

    def _rescore_pending(self):
        """Re-score all pending experiments against updated Pareto archive."""
        pending = self.coordinator.list_work(status=WorkItemStatus.PENDING, limit=MAX_PENDING_SCAN)
        for item in pending:
            new_score = self.score_experiment(item)
            self.coordinator.update_priority(item.item_id, new_score)

    def get_archive_state(self) -> dict:
        """Return current Pareto archive state for worker consumption."""
        return {
            "frontier_size": len(self.archive.entries),
            "hypervolume": self.archive.hypervolume(),
            "entries": [
                {
                    "item_id": e.item_id,
                    "objectives": e.objectives,
                    "species": e.species,
                    "config": e.config,
                }
                for e in self.archive.entries
            ],
            "species_counts": dict(self._species_counts),
            "total_validated": len(self._validated_configs),
        }

    def species_effectiveness(self) -> dict[str, float]:
        """Compute effectiveness rate per species (fraction of frontier contributions)."""
        if not self._validated_configs:
            return {}
        frontier_ids = {e.item_id for e in self.archive.entries}
        effectiveness = {}
        for species, count in self._species_counts.items():
            frontier_count = sum(
                1 for e in self.archive.entries if e.species == species
            )
            effectiveness[species] = frontier_count / count if count else 0.0
        return effectiveness
