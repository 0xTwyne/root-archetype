#!/usr/bin/env python3
"""Validate all skills in .claude/skills/ against archetype standards.

Checks:
- SKILL.md exists (exact case)
- Valid YAML frontmatter with --- delimiters
- name field: present, kebab-case, matches folder name
- description field: present, under 1024 chars, no XML angle brackets, contains trigger phrase
- allowed-tools field (if present): validates Tool(pattern) syntax
- Gotchas section exists (## Gotchas or ## Common Issues)
- No README.md inside skill folder
- SKILL.md under 5000 words (warning)
"""

import os
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILLS_DIR = REPO_ROOT / ".claude" / "skills"
CANONICAL_SKILLS_DIR = REPO_ROOT / "agents" / "skills"
KEBAB_RE = re.compile(r"^[a-z][a-z0-9]*(-[a-z0-9]+)*$")
TOOL_PATTERN_RE = re.compile(r"^[A-Za-z]+\(.*\)$")
TRIGGER_PHRASES = ["Use when", "Trigger when", "TRIGGER when", "Do NOT use"]


def parse_frontmatter(text):
    """Extract YAML frontmatter from markdown text. Returns (dict, body) or (None, text)."""
    if not text.startswith("---"):
        return None, text
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None, text
    frontmatter = {}
    for line in parts[1].strip().splitlines():
        if ":" in line:
            key, _, value = line.partition(":")
            frontmatter[key.strip()] = value.strip().strip('"').strip("'")
    return frontmatter, parts[2]


def validate_skill(skill_dir):
    """Validate a single skill directory. Returns list of (level, message) tuples."""
    issues = []
    name = skill_dir.name

    # Check SKILL.md exists
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        # Check for wrong case
        for f in skill_dir.iterdir():
            if f.name.lower() == "skill.md" and f.name != "SKILL.md":
                issues.append(("ERROR", f"Found {f.name} but expected exact case SKILL.md"))
                return issues
        issues.append(("ERROR", "SKILL.md not found"))
        return issues

    text = skill_md.read_text(encoding="utf-8")

    # Detect thin wrapper pattern — defer content checks to canonical file
    is_wrapper = "agents/skills/" in text and "Read and follow" in text
    canonical_text = ""
    if is_wrapper:
        canonical = CANONICAL_SKILLS_DIR / name / "SKILL.md"
        if canonical.exists():
            canonical_text = canonical.read_text(encoding="utf-8")
        else:
            issues.append(("ERROR", f"Wrapper references agents/skills/{name}/SKILL.md but file not found"))
            return issues

    # Check frontmatter
    fm, body = parse_frontmatter(text)
    if fm is None:
        issues.append(("ERROR", "No YAML frontmatter (must start with ---)"))
        return issues

    # Check name field
    if "name" not in fm:
        issues.append(("ERROR", "Missing 'name' field in frontmatter"))
    else:
        fm_name = fm["name"]
        if not KEBAB_RE.match(fm_name):
            issues.append(("ERROR", f"name '{fm_name}' is not valid kebab-case"))
        if fm_name != name:
            issues.append(("ERROR", f"name '{fm_name}' does not match folder name '{name}'"))

    # Check description field
    if "description" not in fm:
        issues.append(("ERROR", "Missing 'description' field in frontmatter"))
    else:
        desc = fm["description"]
        if len(desc) > 1024:
            issues.append(("ERROR", f"description is {len(desc)} chars (max 1024)"))
        if "<" in desc or ">" in desc:
            issues.append(("ERROR", "description contains XML angle brackets"))
        if not any(phrase.lower() in desc.lower() for phrase in TRIGGER_PHRASES):
            issues.append(("WARN", "description lacks trigger phrase (e.g. 'Use when', 'Do NOT use')"))

    # Check allowed-tools format if present
    if "allowed-tools" in fm:
        for tool_spec in fm["allowed-tools"].split(","):
            tool_spec = tool_spec.strip()
            if tool_spec and not TOOL_PATTERN_RE.match(tool_spec):
                issues.append(("ERROR", f"allowed-tools entry '{tool_spec}' doesn't match Tool(pattern) format"))

    # Check for Gotchas section (in canonical file for wrappers, in body for standalone)
    gotchas_pattern = re.compile(r"^##\s+(Gotchas|Common Issues)", re.MULTILINE)
    check_text = canonical_text if is_wrapper else body
    if not gotchas_pattern.search(check_text):
        issues.append(("ERROR", "Missing ## Gotchas or ## Common Issues section"))

    # Check no README.md
    readme = skill_dir / "README.md"
    if readme.exists():
        issues.append(("WARN", "README.md found inside skill folder (use SKILL.md only)"))

    # Word count warning
    word_count = len(body.split())
    if word_count > 5000:
        issues.append(("WARN", f"SKILL.md body is {word_count} words (recommended max 5000)"))

    return issues


def main():
    if not SKILLS_DIR.exists():
        print(f"Skills directory not found: {SKILLS_DIR}")
        sys.exit(1)

    skill_dirs = sorted(
        d for d in SKILLS_DIR.iterdir()
        if d.is_dir() and not d.name.startswith(".")
    )

    if not skill_dirs:
        print(f"No skill directories found in {SKILLS_DIR}")
        sys.exit(0)

    errors = 0
    warnings = 0

    for skill_dir in skill_dirs:
        issues = validate_skill(skill_dir)
        if not issues:
            print(f"  OK  {skill_dir.name}")
            continue

        for level, msg in issues:
            prefix = "ERROR" if level == "ERROR" else " WARN"
            print(f"{prefix} {skill_dir.name}: {msg}")
            if level == "ERROR":
                errors += 1
            else:
                warnings += 1

    # Check that each .claude/skills/ wrapper has a corresponding agents/skills/ canonical
    if CANONICAL_SKILLS_DIR.exists():
        for skill_dir in skill_dirs:
            canonical = CANONICAL_SKILLS_DIR / skill_dir.name / "SKILL.md"
            if not canonical.exists():
                print(f" WARN {skill_dir.name}: no canonical definition at agents/skills/{skill_dir.name}/SKILL.md")
                warnings += 1

    print(f"\n{len(skill_dirs)} skills checked: {errors} errors, {warnings} warnings")

    if errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
