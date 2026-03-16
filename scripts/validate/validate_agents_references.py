#!/usr/bin/env python3
"""Validate local markdown references in governance files."""

import re
import sys
from pathlib import Path

def find_references(content: str) -> list[str]:
    """Extract local file references from markdown."""
    refs = []
    # Backtick refs: `path/file.md`
    refs.extend(re.findall(r'`([^`]+\.(?:md|sh|py|json|yaml|yml))`', content))
    # Link refs: [text](path/file.md)
    refs.extend(re.findall(r'\[[^\]]*\]\(([^)]+\.(?:md|sh|py|json|yaml|yml))\)', content))
    return refs

# Known parent directories for basename-style references in documentation.
# When a ref is a bare filename, also check under these directories.
_BASENAME_SEARCH_DIRS = [
    "scripts/hooks",
    "scripts/validate",
    "scripts/utils",
    "scripts/session",
    "scripts/repos",
    ".claude/commands",
    ".claude/skills",
    "agents/shared",
    "agents",
]


def _is_non_path_ref(ref: str) -> bool:
    """Return True if ref is not a resolvable filesystem path."""
    # Template patterns (YYYY-MM, {{VAR}})
    if "YYYY" in ref or "{{" in ref:
        return True
    # Home-dir paths
    if ref.startswith("~"):
        return True
    # Glob patterns
    if "*" in ref:
        return True
    # Inline code with spaces (commands, not paths)
    if " " in ref:
        return True
    # Instructional placeholders (e.g. "your-role.md", "my-app")
    if "your-" in ref or "my-" in ref or "example" in ref.lower():
        return True
    return False


def validate():
    repo_root = Path(__file__).resolve().parent.parent.parent
    scan_patterns = [
        "agents/README.md",
        "agents/AGENT_INSTRUCTIONS.md",
        "CLAUDE.md",
    ]

    broken = []
    for pattern in scan_patterns:
        f = repo_root / pattern
        if not f.exists():
            continue
        content = f.read_text()
        for ref in find_references(content):
            if ref.startswith(("http://", "https://")):
                continue
            if _is_non_path_ref(ref):
                continue
            # Try: relative to file, repo root, and basename search dirs
            resolved = f.parent / ref
            if resolved.exists() or (repo_root / ref).exists():
                continue
            # Basename fallback — check known parent directories
            basename = Path(ref).name
            found = any(
                (repo_root / d / basename).exists()
                for d in _BASENAME_SEARCH_DIRS
            )
            if not found:
                broken.append((f.name, ref))

    if broken:
        print("Reference validation FAILED — broken references:")
        for source, ref in broken:
            print(f"  {source} → {ref}")
        return False
    else:
        print("Reference validation passed")
        return True

if __name__ == "__main__":
    sys.exit(0 if validate() else 1)
