#!/usr/bin/env python3
"""Validate that all agent role files contain required sections."""

import sys
from pathlib import Path

REQUIRED_SECTIONS = [
    "## Mission",
    "## Use This Role When",
    "## Inputs Required",
    "## Outputs",
    "## Workflow",
    "## Guardrails",
]

EXCLUDED = {"README.md", "AGENT_INSTRUCTIONS.md"}

def validate():
    repo_root = Path(__file__).resolve().parent.parent.parent
    agents_dir = repo_root / "agents"

    if not agents_dir.exists():
        print("No agents/ directory found")
        return True

    roles_dir = agents_dir / "roles"
    if not roles_dir.exists():
        print("No agents/roles/ directory found")
        return True

    failures = []
    for f in sorted(roles_dir.glob("*.md")):
        if f.name in EXCLUDED:
            continue
        content = f.read_text()
        missing = [s for s in REQUIRED_SECTIONS if s not in content]
        if missing:
            failures.append((f.name, missing))

    if failures:
        print("Agent structure validation FAILED:")
        for name, missing in failures:
            print(f"  {name}: missing {missing}")
        return False
    else:
        print("Agent structure validation passed")
        return True

if __name__ == "__main__":
    sys.exit(0 if validate() else 1)
