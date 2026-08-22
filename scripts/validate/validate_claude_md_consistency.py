#!/usr/bin/env python3
"""Validate agent instruction files match actual filesystem state.

Checks that every file/directory referenced in AGENT.md (primary) and
CLAUDE.md (engine pointer) actually exists, and that section inventories
(hooks, validators, commands, skills) match what's on disk.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent

# Sections that enumerate filesystem artifacts.
# Each entry: (section_heading, directory, glob_pattern, description)
INVENTORY_SECTIONS = [
    ("Hooks", "scripts/hooks", "*.sh", "hook scripts"),
    ("Validators", "scripts/validate", "*.py", "validator scripts"),
    ("Commands", ".claude/commands", "*.md", "command definitions"),
    ("Skills", ".claude/skills", "*/", "skill directories"),
]


def _gitignored(refs: list) -> set:
    """Return the subset of refs that git ignores.

    A documented path that git ignores is absent from a fresh clone by design,
    so it can never be a broken reference. Requiring it makes this validator
    pass on a configured machine and fail on a clone.
    """
    import subprocess
    if not refs:
        return set()
    try:
        proc = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "check-ignore", "--stdin"],
            input="\n".join(refs), capture_output=True, text=True, timeout=15,
        )
    except Exception:
        return set()
    if proc.returncode not in (0, 1):
        return set()
    return {line.strip() for line in proc.stdout.splitlines() if line.strip()}


def extract_backtick_refs(text: str) -> list[str]:
    """Extract backtick-quoted paths from text."""
    return re.findall(r'`([^`]+(?:\.(?:sh|py|json|yaml|yml|md)|/))`', text)


# Backtick refs that are basenames listed under a heading that
# already provides the parent directory. Map heading keyword → dir.
_SECTION_DIRS = {
    "hooks": "scripts/hooks",
    "validators": "scripts/validate",
    "commands": ".claude/commands",
    "skills": ".claude/skills",
    "agent system": "agents",
    "governance": "scripts",
}


def check_referenced_paths(content: str) -> list[str]:
    """Check that backtick-quoted paths exist on disk."""
    errors: list[str] = []
    missing: list[str] = []

    # Build set of basenames that appear under known section headings
    section_basenames: set[str] = set()
    current_section = ""
    for line in content.splitlines():
        heading_match = re.match(r'^#{1,4}\s+(.+)', line)
        if heading_match:
            current_section = heading_match.group(1).lower()
        for ref in extract_backtick_refs(line):
            for keyword, parent_dir in _SECTION_DIRS.items():
                if keyword in current_section:
                    full = REPO_ROOT / parent_dir / ref
                    if full.exists():
                        section_basenames.add(ref)

    for ref in extract_backtick_refs(content):
        # Skip template variables
        if "{{" in ref:
            continue
        # Skip placeholder paths (e.g. <user>, {name})
        if "<" in ref or "{" in ref:
            continue
        # Skip command examples and inline code
        if " " in ref:
            continue
        # Skip YYYY-MM patterns
        if "YYYY" in ref:
            continue
        # Skip home-dir paths
        if ref.startswith("~"):
            continue
        # Skip basenames resolvable under section context
        if ref in section_basenames:
            continue
        path = REPO_ROOT / ref
        if not path.exists():
            missing.append(ref)

    # Drop anything git ignores — absent from a clone by design, not broken.
    ignored = _gitignored(sorted(set(missing)))
    errors.extend(
        f"Referenced path does not exist: `{ref}`"
        for ref in missing
        if ref not in ignored
    )
    return errors


def check_inventory_completeness(combined_content: str) -> list[str]:
    """Check that instruction files list all artifacts on disk.

    If the directory path itself is mentioned (e.g. `scripts/hooks/`),
    that counts as covering all contents — AGENT.md is deliberately
    concise and points to directories, not individual files.
    """
    errors = []
    for section, directory, pattern, desc in INVENTORY_SECTIONS:
        dir_path = REPO_ROOT / directory
        if not dir_path.exists():
            continue

        # If the directory path is mentioned, all contents are covered
        if f"`{directory}/" in combined_content or f"`{directory}`" in combined_content:
            continue
        # Also check without backticks (in prose)
        if f"{directory}/" in combined_content:
            continue

        if pattern == "*/":
            actual = {p.name for p in dir_path.iterdir() if p.is_dir()}
        else:
            actual = {p.name for p in dir_path.glob(pattern)}

        # Check against combined content of AGENT.md + CLAUDE.md
        mentioned = set()
        for name in actual:
            if name in combined_content:
                mentioned.add(name)

        unlisted = actual - mentioned
        if unlisted:
            errors.append(
                f"{section}: {len(unlisted)} on-disk {desc} not mentioned in AGENT.md or CLAUDE.md: {sorted(unlisted)}"
            )
    return errors


def check_planned_markers(content: str) -> list[str]:
    """Flag items still marked 'planned' that now exist on disk."""
    errors = []
    for match in re.finditer(r'-\s+(.+?)\(planned.*?\)', content):
        line = match.group(0)
        refs = re.findall(r'`([^`]+)`', line)
        for ref in refs:
            path = REPO_ROOT / ref
            if path.exists():
                errors.append(
                    f"Marked as 'planned' but exists on disk: `{ref}`"
                )
    return errors


def validate() -> bool:
    # Read both instruction files
    agent_md_path = REPO_ROOT / "AGENT.md"
    claude_md_path = REPO_ROOT / "CLAUDE.md"

    contents = []
    for path in [agent_md_path, claude_md_path]:
        if path.exists():
            contents.append(path.read_text())

    if not contents:
        print("No AGENT.md or CLAUDE.md found — skipping consistency check")
        return True

    combined = "\n".join(contents)
    all_errors = []

    for content in contents:
        all_errors.extend(check_referenced_paths(content))
    all_errors.extend(check_inventory_completeness(combined))
    for content in contents:
        all_errors.extend(check_planned_markers(content))

    if all_errors:
        print("Instruction file consistency validation FAILED:")
        for err in all_errors:
            print(f"  {err}")
        return False
    else:
        print("Instruction file consistency validation passed")
        return True


if __name__ == "__main__":
    sys.exit(0 if validate() else 1)
