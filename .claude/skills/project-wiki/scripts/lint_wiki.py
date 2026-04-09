#!/usr/bin/env python3
"""Lint the project knowledge base for governance hygiene issues.

Runs 5 lint passes against handoffs, intake index, and cross-references.
Reads thresholds from wiki.yaml, falls back to sensible defaults.

Exit code: 1 if any ERRORs found, 0 otherwise.
"""

from __future__ import annotations

import os
import re
import sys
import time
from datetime import date, datetime
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml")
    sys.exit(1)

def _find_project_root() -> Path:
    """Walk up from this file to find project root (contains wiki.yaml or .git)."""
    current = Path(__file__).resolve().parent
    for _ in range(10):  # Max 10 levels up
        if (current / "wiki.yaml").exists() or (current / ".git").exists():
            return current
        parent = current.parent
        if parent == current:
            break
        current = parent
    # Fallback: assume 4 levels up (original behavior)
    return Path(__file__).resolve().parents[4]

ROOT = _find_project_root()

# Severity levels
ERROR = "ERROR"
WARNING = "WARNING"
INFO = "INFO"

Issue = tuple[str, str, str]  # (severity, file, message)


def load_wiki_config() -> dict:
    """Load wiki.yaml from repo root. Returns empty dict if not found."""
    wiki_path = ROOT / "wiki.yaml"
    if wiki_path.exists():
        with open(wiki_path) as f:
            return yaml.safe_load(f) or {}
    return {}


def _get_lint_config(config: dict) -> dict:
    """Extract lint thresholds from config with defaults."""
    lint = config.get("lint", {})
    return {
        "stale_days": lint.get("stale_days", 30),
        "aging_days": lint.get("aging_days", 14),
        "unactioned_intake_days": lint.get("unactioned_intake_days", 7),
        "enabled_passes": lint.get("enabled_passes", [
            "orphan_handoffs", "stale_entries", "contradictory_status",
            "unactioned_intake", "missing_cross_refs",
        ]),
        "paths": lint.get("paths", {}),
        "index_patterns": lint.get("index_patterns", ["*-index.md"]),
    }


def _extract_md_links(content: str) -> list[str]:
    """Extract markdown link targets from content: [text](target.md)."""
    return re.findall(r'\[(?:[^\]]*)\]\(([^)]+\.md)\)', content)


def _extract_referenced_handoffs(active_dir: Path, extra_index_patterns: list[str] | None = None) -> set[str]:
    """Parse index files and extract referenced handoff filenames.
    
    Scans files matching extra_index_patterns (default: ["*-index.md"]).
    """
    patterns = extra_index_patterns or ["*-index.md"]
    referenced = set()
    seen_files: set[Path] = set()
    for pattern in patterns:
        for index_file in active_dir.glob(pattern):
            if index_file in seen_files:
                continue
            seen_files.add(index_file)
            file_content = index_file.read_text(errors="replace")
            for link in _extract_md_links(file_content):
                # Normalize: strip relative paths, keep just filename
                referenced.add(Path(link).name)
    return referenced


def check_orphan_handoffs(active_dir: Path, index_patterns: list[str] | None = None) -> list[Issue]:
    """Pass 1: Find handoff files not referenced by any index."""
    issues: list[Issue] = []
    patterns = index_patterns or ["*-index.md"]
    referenced = _extract_referenced_handoffs(active_dir, patterns)

    # Index files themselves are not orphans
    index_files: set[str] = set()
    for pattern in patterns:
        index_files.update(f.name for f in active_dir.glob(pattern))

    for md_file in sorted(active_dir.glob("*.md")):
        name = md_file.name
        if name in index_files:
            continue
        if name not in referenced:
            issues.append((WARNING, name, "Not referenced by any index file (orphan)"))

    return issues


def check_stale_entries(active_dir: Path, aging_days: int, stale_days: int) -> list[Issue]:
    """Pass 2: Flag files not modified recently."""
    issues: list[Issue] = []
    now = time.time()

    for md_file in sorted(active_dir.glob("*.md")):
        age_days = int((now - md_file.stat().st_mtime) / 86400)
        if age_days > stale_days:
            issues.append((ERROR, md_file.name, f"STALE ({age_days}d, threshold {stale_days}d)"))
        elif age_days > aging_days:
            issues.append((WARNING, md_file.name, f"Aging ({age_days}d, threshold {aging_days}d)"))

    return issues


def check_contradictory_status(active_dir: Path, completed_dir: Path) -> list[Issue]:
    """Pass 3: Flag status vs directory mismatches."""
    issues: list[Issue] = []
    # Match status lines that START with a done keyword (not "active (X complete, Y pending)")
    done_start = re.compile(r'^(completed|archived|done)\b', re.IGNORECASE)
    active_pattern = re.compile(r'\b(active|in.progress)\b', re.IGNORECASE)

    # Check active/ files claiming to be done
    for md_file in sorted(active_dir.glob("*.md")):
        content = md_file.read_text(errors="replace")
        status_match = re.search(r'\*\*Status\*\*:\s*(.+)', content)
        if status_match:
            status_text = status_match.group(1).strip()
            if done_start.search(status_text):
                issues.append((ERROR, md_file.name,
                    f"In active/ but status says '{status_text}' — should be moved to completed/"))

    # Check completed/ files claiming to be active
    if completed_dir.exists():
        for md_file in sorted(completed_dir.glob("*.md")):
            content = md_file.read_text(errors="replace")
            status_match = re.search(r'\*\*Status\*\*:\s*(.+)', content)
            if status_match:
                status_text = status_match.group(1).strip()
                if active_pattern.search(status_text) and not done_start.search(status_text):
                    issues.append((WARNING, f"completed/{md_file.name}",
                        f"In completed/ but status says '{status_text}'"))

    return issues


def check_unactioned_intake(index_path: Path, max_age_days: int) -> list[Issue]:
    """Pass 4: Find intake entries that should have handoffs but don't."""
    issues: list[Issue] = []
    if not index_path.exists():
        return issues

    with open(index_path) as f:
        entries = yaml.safe_load(f)
    if not isinstance(entries, list):
        entries = entries.get("entries", []) if isinstance(entries, dict) else []

    today = date.today()
    actionable_verdicts = {"worth_investigating", "new_opportunity"}

    for entry in entries:
        verdict = entry.get("verdict", "")
        if verdict not in actionable_verdicts:
            continue
        if entry.get("handoffs_created"):
            continue

        ingested = entry.get("ingested_date", "")
        if not ingested:
            continue
        try:
            ingested_date = datetime.strptime(str(ingested), "%Y-%m-%d").date()
        except (ValueError, TypeError):
            continue

        age = (today - ingested_date).days
        if age > max_age_days:
            eid = entry.get("id", "unknown")
            title = entry.get("title", "untitled")[:60]
            issues.append((WARNING, eid,
                f"verdict='{verdict}', no handoff created, {age}d old: {title}"))

    return issues


def check_missing_crossrefs(active_dir: Path, completed_dir: Path) -> list[Issue]:
    """Pass 5: Check that markdown links in handoffs point to existing files."""
    issues: list[Issue] = []

    for md_file in sorted(active_dir.glob("*.md")):
        content = md_file.read_text(errors="replace")
        for link in _extract_md_links(content):
            # Skip external links and anchors
            if link.startswith("http") or link.startswith("#") or link.startswith("/"):
                continue
            # Resolve relative to the handoff's directory
            target_name = Path(link).name
            # Check in active/ and completed/
            found = (active_dir / target_name).exists()
            if not found and completed_dir.exists():
                found = (completed_dir / target_name).exists()
            # Also check parent-relative paths like ../completed/foo.md
            if not found:
                resolved = (active_dir / link).resolve()
                found = resolved.exists()
            if not found:
                issues.append((ERROR, md_file.name,
                    f"Broken link: [{link}] target not found"))

    return issues


def main() -> int:
    config = load_wiki_config()
    lint_cfg = _get_lint_config(config)
    enabled = set(lint_cfg["enabled_passes"])

    # Configurable paths with defaults
    paths_cfg = lint_cfg.get("paths", {})
    active_dir = ROOT / paths_cfg.get("active_handoffs", "handoffs/active")
    completed_dir = ROOT / paths_cfg.get("completed_handoffs", "handoffs/completed")
    index_path = ROOT / paths_cfg.get("intake_index", "research/intake_index.yaml")
    index_patterns = lint_cfg.get("index_patterns", ["*-index.md"])

    if not active_dir.exists():
        print(f"ERROR: Active handoffs directory not found at {active_dir}")
        return 1

    all_issues: list[Issue] = []
    pass_names = []

    # Pass 1: Orphan handoffs
    if "orphan_handoffs" in enabled:
        issues = check_orphan_handoffs(active_dir, index_patterns)
        all_issues.extend(issues)
        pass_names.append(("Orphan handoffs", issues))

    # Pass 2: Stale entries
    if "stale_entries" in enabled:
        issues = check_stale_entries(active_dir, lint_cfg["aging_days"], lint_cfg["stale_days"])
        all_issues.extend(issues)
        pass_names.append(("Stale entries", issues))

    # Pass 3: Contradictory status
    if "contradictory_status" in enabled:
        issues = check_contradictory_status(active_dir, completed_dir)
        all_issues.extend(issues)
        pass_names.append(("Contradictory status", issues))

    # Pass 4: Un-actioned intake
    if "unactioned_intake" in enabled:
        issues = check_unactioned_intake(index_path, lint_cfg["unactioned_intake_days"])
        all_issues.extend(issues)
        pass_names.append(("Un-actioned intake", issues))

    # Pass 5: Missing cross-refs
    if "missing_cross_refs" in enabled:
        issues = check_missing_crossrefs(active_dir, completed_dir)
        all_issues.extend(issues)
        pass_names.append(("Missing cross-refs", issues))

    # Print report
    print("=" * 70)
    print("  Knowledge Base Lint Report")
    print("=" * 70)
    print()

    for pass_name, issues in pass_names:
        errors = [i for i in issues if i[0] == ERROR]
        warnings = [i for i in issues if i[0] == WARNING]
        print(f"### {pass_name}: {len(errors)} errors, {len(warnings)} warnings")
        if not issues:
            print("  (clean)")
        for severity, target, msg in issues:
            print(f"  [{severity}] {target}: {msg}")
        print()

    # Summary
    total_errors = sum(1 for i in all_issues if i[0] == ERROR)
    total_warnings = sum(1 for i in all_issues if i[0] == WARNING)
    print("-" * 70)
    print(f"Summary: {total_errors} errors, {total_warnings} warnings")

    if total_errors > 0:
        print("FAILED: Fix errors above before proceeding.")
        return 1

    print("PASSED: No errors found.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
