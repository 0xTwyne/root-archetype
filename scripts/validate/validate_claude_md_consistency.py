#!/usr/bin/env python3
"""Validate CLAUDE.md claims match actual filesystem state.

Checks that every file/directory referenced in CLAUDE.md actually exists,
and that section inventories (hooks, validators, commands, skills) match
what's on disk.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Sections in CLAUDE.md that enumerate filesystem artifacts.
# Each entry: (section_heading, directory, glob_pattern, description)
INVENTORY_SECTIONS = [
    ("Hooks", "scripts/hooks", "*.sh", "hook scripts"),
    ("Validators", "scripts/validate", "*.py", "validator scripts"),
    ("Commands", ".claude/commands", "*.md", "command definitions"),
    ("Skills", ".claude/skills", "*/", "skill directories"),
]


def extract_backtick_refs(text: str) -> list[str]:
    """Extract backtick-quoted paths from text."""
    return re.findall(r'`([^`]+(?:\.(?:sh|py|json|yaml|yml|md)|/))`', text)


# Backtick refs in CLAUDE.md that are basenames listed under a heading that
# already provides the parent directory. Map heading keyword → dir.
_SECTION_DIRS = {
    "hooks": "scripts/hooks",
    "validators": "scripts/validate",
    "commands": ".claude/commands",
    "skills": ".claude/skills",
    "agent system": "agents",
}


def check_referenced_paths(claude_md: str) -> list[str]:
    """Check that backtick-quoted paths in CLAUDE.md exist on disk."""
    errors = []

    # Build set of basenames that appear under known section headings
    section_basenames: set[str] = set()
    current_section = ""
    for line in claude_md.splitlines():
        heading_match = re.match(r'^#{1,4}\s+(.+)', line)
        if heading_match:
            current_section = heading_match.group(1).lower()
        for ref in extract_backtick_refs(line):
            # Check if this is a basename under a known section
            for keyword, parent_dir in _SECTION_DIRS.items():
                if keyword in current_section:
                    full = REPO_ROOT / parent_dir / ref
                    if full.exists():
                        section_basenames.add(ref)

    for ref in extract_backtick_refs(claude_md):
        # Skip template variables
        if "{{" in ref:
            continue
        # Skip command examples and inline code
        if " " in ref:
            continue
        # Skip YYYY-MM patterns
        if "YYYY" in ref:
            continue
        # Skip home-dir paths (e.g. ~/.gitnexus/)
        if ref.startswith("~"):
            continue
        # Skip basenames resolvable under section context
        if ref in section_basenames:
            continue
        path = REPO_ROOT / ref
        if not path.exists():
            errors.append(f"Referenced path does not exist: `{ref}`")
    return errors


def check_inventory_completeness(claude_md: str) -> list[str]:
    """Check that CLAUDE.md lists all artifacts that exist on disk."""
    errors = []
    for section, directory, pattern, desc in INVENTORY_SECTIONS:
        dir_path = REPO_ROOT / directory
        if not dir_path.exists():
            continue

        if pattern == "*/":
            actual = {p.name for p in dir_path.iterdir() if p.is_dir()}
        else:
            actual = {p.name for p in dir_path.glob(pattern)}

        # Find what CLAUDE.md mentions from this directory
        mentioned = set()
        for name in actual:
            if name in claude_md:
                mentioned.add(name)

        unlisted = actual - mentioned
        if unlisted:
            errors.append(
                f"{section}: {len(unlisted)} on-disk {desc} not mentioned in CLAUDE.md: {sorted(unlisted)}"
            )
    return errors


def check_planned_markers(claude_md: str) -> list[str]:
    """Flag items still marked 'planned' that now exist on disk."""
    errors = []
    for match in re.finditer(r'-\s+(.+?)\(planned.*?\)', claude_md):
        line = match.group(0)
        # Extract backtick refs from this line
        refs = re.findall(r'`([^`]+)`', line)
        for ref in refs:
            path = REPO_ROOT / ref
            if path.exists():
                errors.append(
                    f"Marked as 'planned' but exists on disk: `{ref}`"
                )
    return errors


def validate() -> bool:
    claude_md_path = REPO_ROOT / "CLAUDE.md"
    if not claude_md_path.exists():
        print("No CLAUDE.md found — skipping consistency check")
        return True

    content = claude_md_path.read_text()
    all_errors = []

    all_errors.extend(check_referenced_paths(content))
    all_errors.extend(check_inventory_completeness(content))
    all_errors.extend(check_planned_markers(content))

    if all_errors:
        print("CLAUDE.md consistency validation FAILED:")
        for err in all_errors:
            print(f"  {err}")
        return False
    else:
        print("CLAUDE.md consistency validation passed")
        return True


if __name__ == "__main__":
    sys.exit(0 if validate() else 1)
