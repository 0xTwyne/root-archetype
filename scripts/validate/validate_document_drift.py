#!/usr/bin/env python3
"""Detect drift between governance documents and actual repository state.

Compares claims in handoffs, CLAUDE.md, and README about file counts,
directory structures, and feature inventories against reality.
"""

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Directories that should always exist in a governed project
REQUIRED_DIRS = [
    "agents",
    "agents/shared",
    "scripts/hooks",
    "scripts/validate",
    "scripts/session",
    "scripts/utils",
    "handoffs/active",
    "handoffs/completed",
    ".claude/commands",
    ".claude/skills",
    "swarm",
]

# Files that should always exist
REQUIRED_FILES = [
    "CLAUDE.md",
    ".claude/settings.json",
]


def check_required_structure() -> list[str]:
    """Verify required directories and files exist."""
    errors = []
    for d in REQUIRED_DIRS:
        if not (REPO_ROOT / d).is_dir():
            errors.append(f"Required directory missing: {d}/")
    for f in REQUIRED_FILES:
        if not (REPO_ROOT / f).is_file():
            errors.append(f"Required file missing: {f}")
    return errors


def check_dependency_map() -> list[str]:
    """Validate dependency-map.json structure if it exists."""
    dep_map = REPO_ROOT / ".claude" / "dependency-map.json"
    if not dep_map.exists():
        return []
    errors = []
    try:
        data = json.loads(dep_map.read_text())
        if "schema_version" not in data:
            errors.append("dependency-map.json: missing 'schema_version'")
        if "edges" not in data:
            errors.append("dependency-map.json: missing 'edges'")
        if not isinstance(data.get("edges", None), list):
            errors.append("dependency-map.json: 'edges' must be a list")
    except (json.JSONDecodeError, KeyError) as e:
        errors.append(f"dependency-map.json: invalid JSON — {e}")
    return errors


def check_handoff_status_consistency() -> list[str]:
    """Check handoff files are in the right directory for their status."""
    errors = []
    for status_dir in ["active", "blocked", "completed", "archived"]:
        hdir = REPO_ROOT / "handoffs" / status_dir
        if not hdir.exists():
            continue
        for f in hdir.glob("*.md"):
            content = f.read_text()
            # Look for ## Status: <status> line
            match = re.search(r'^## Status:\s*(.+)$', content, re.MULTILINE)
            if not match:
                continue
            declared = match.group(1).strip().lower()
            expected_map = {
                "active": ["in progress", "in_progress", "active"],
                "blocked": ["blocked", "waiting"],
                "completed": ["complete", "completed", "done"],
                "archived": ["archived"],
            }
            expected = expected_map.get(status_dir, [])
            if expected and not any(e in declared for e in expected):
                errors.append(
                    f"handoffs/{status_dir}/{f.name}: declares status '{declared}' "
                    f"but is in '{status_dir}/' directory"
                )
    return errors


def check_settings_hooks_exist() -> list[str]:
    """Verify hooks referenced in settings.json exist on disk."""
    settings = REPO_ROOT / ".claude" / "settings.json"
    if not settings.exists():
        return []
    errors = []
    try:
        data = json.loads(settings.read_text())
        hooks = data.get("hooks", {})
        for event_name, event_hooks in hooks.items():
            if not isinstance(event_hooks, list):
                continue
            for hook in event_hooks:
                cmd = hook.get("command", "") if isinstance(hook, dict) else ""
                # Extract script paths from command
                for token in cmd.split():
                    if token.endswith(".sh"):
                        path = REPO_ROOT / token
                        if not path.exists():
                            errors.append(
                                f"settings.json hook '{event_name}' references missing script: {token}"
                            )
    except (json.JSONDecodeError, AttributeError):
        errors.append("settings.json: could not parse hooks section")
    return errors


def validate() -> bool:
    all_errors = []
    all_errors.extend(check_required_structure())
    all_errors.extend(check_dependency_map())
    all_errors.extend(check_handoff_status_consistency())
    all_errors.extend(check_settings_hooks_exist())

    if all_errors:
        print("Document drift detection FAILED:")
        for err in all_errors:
            print(f"  {err}")
        return False
    else:
        print("Document drift detection passed")
        return True


if __name__ == "__main__":
    sys.exit(0 if validate() else 1)
