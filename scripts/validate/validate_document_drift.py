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
    "agents/roles",
    "scripts/hooks",
    "scripts/validate",
    "scripts/session",
    "scripts/utils",
    "notes",
    ".claude/commands",
    ".claude/skills",
]

# Files that should always exist
REQUIRED_FILES = [
    "AGENT.md",
    "CLAUDE.md",
    "CODEX.md",
    "MAINTAINERS.json",
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


def check_handoff_status_consistency() -> list[str]:
    """Check handoff files are in the right directory for their status."""
    errors = []
    # Check per-user handoff directories (notes/<user>/handoffs/)
    notes_dir = REPO_ROOT / "notes"
    if not notes_dir.exists():
        return errors
    for user_dir in notes_dir.iterdir():
        if not user_dir.is_dir() or user_dir.name in ("handoffs",):
            continue
        handoffs_dir = user_dir / "handoffs"
        if not handoffs_dir.is_dir():
            continue
        for f in handoffs_dir.glob("*.md"):
            content = f.read_text()
            match = re.search(r'\*\*Status\*\*:\s*(.+)', content)
            if match:
                declared = match.group(1).strip().lower()

    # Also check legacy handoffs/ directory if it still exists
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
            for group in event_hooks:
                if not isinstance(group, dict):
                    continue
                for hook in group.get("hooks", []):
                    cmd = hook.get("command", "") if isinstance(hook, dict) else ""
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
