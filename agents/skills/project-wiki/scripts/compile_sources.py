#!/usr/bin/env python3
"""List source files for wiki compilation.

Scans per-user streams (logs/progress, notes) and outputs a JSON manifest
of files that need to be compiled into shared knowledge. Compares file
modification times against the last compilation timestamp.

Usage:
    python3 compile_sources.py              # incremental (since last compile)
    python3 compile_sources.py --full       # all sources regardless of timestamp
    python3 compile_sources.py --touch      # update .last_compile after output
    python3 compile_sources.py --type plan  # filter by source type
    python3 compile_sources.py --since 2026-04-01  # override since-date
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path


def _find_project_root() -> Path:
    """Walk up from this file to find project root (contains wiki.yaml or .git)."""
    current = Path(__file__).resolve().parent
    for _ in range(10):
        if (current / "wiki.yaml").exists() or (current / ".git").exists():
            return current
        parent = current.parent
        if parent == current:
            break
        current = parent
    return Path(__file__).resolve().parents[4]


ROOT = _find_project_root()

LAST_COMPILE_PATH = ROOT / "knowledge" / "research" / ".last_compile"

# Source type definitions: (base_dir, subdirectory pattern, type label)
# Each entry is scanned relative to ROOT.
SOURCE_DIRS = [
    ("logs/progress", None, "progress"),
    ("notes", "handoffs/completed", "handoff-completed"),
    ("notes", "handoffs/active", "handoff-active"),
    ("notes", "handoffs", "handoff-active"),  # files directly in handoffs/
    ("notes", "plans", "plan"),
    ("notes", "research", "research"),
]

SKIP_FILENAMES = {"INDEX.md", "README.md", ".gitkeep"}


def get_last_compile() -> float:
    """Read .last_compile timestamp. Returns 0.0 if missing (treat all as new)."""
    if not LAST_COMPILE_PATH.exists():
        return 0.0
    try:
        text = LAST_COMPILE_PATH.read_text().strip()
        if not text:
            return 0.0
        dt = datetime.fromisoformat(text.replace("Z", "+00:00"))
        return dt.timestamp()
    except (ValueError, OSError):
        return 0.0


def get_last_compile_iso() -> str | None:
    """Read .last_compile as ISO string, or None if missing."""
    if not LAST_COMPILE_PATH.exists():
        return None
    text = LAST_COMPILE_PATH.read_text().strip()
    return text if text else None


def touch_last_compile() -> None:
    """Write current UTC timestamp to .last_compile."""
    LAST_COMPILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    LAST_COMPILE_PATH.write_text(ts + "\n")


def extract_title(path: Path) -> str:
    """Extract first H1 heading from a markdown file, or return filename."""
    try:
        with open(path, errors="replace") as f:
            for line in f:
                m = re.match(r"^#\s+(.+)", line)
                if m:
                    return m.group(1).strip()
    except OSError:
        pass
    return path.stem


def extract_user(path: Path, base: str) -> str:
    """Extract username from path like notes/<user>/... or logs/progress/<user>/..."""
    try:
        rel = path.relative_to(ROOT / base)
        parts = rel.parts
        if parts:
            return parts[0]
    except ValueError:
        pass
    return "unknown"


def scan_sources(since: float, type_filter: str | None) -> list[dict]:
    """Walk source directories and collect files newer than `since`."""
    seen: set[Path] = set()
    results: list[dict] = []

    for base_dir, subdir, source_type in SOURCE_DIRS:
        if type_filter and source_type != type_filter:
            continue

        base_path = ROOT / base_dir
        if not base_path.exists():
            continue

        # Find user directories under base_path
        for user_dir in sorted(base_path.iterdir()):
            if not user_dir.is_dir():
                continue
            user = user_dir.name

            if subdir:
                scan_dir = user_dir / subdir
            else:
                # For logs/progress/<user>/, scan the user dir directly
                scan_dir = user_dir

            if not scan_dir.is_dir():
                continue

            # Scan only .md files directly in this directory (not recursive)
            # This prevents double-counting: handoffs/ scans direct files,
            # handoffs/completed/ scans its own files separately.
            for md_file in sorted(scan_dir.glob("*.md")):
                if not md_file.is_file():
                    continue
                if md_file.name in SKIP_FILENAMES:
                    continue

                resolved = md_file.resolve()
                if resolved in seen:
                    continue
                seen.add(resolved)

                mtime = md_file.stat().st_mtime
                if mtime <= since:
                    continue

                results.append({
                    "path": str(md_file.relative_to(ROOT)),
                    "user": user,
                    "type": source_type,
                    "modified": datetime.fromtimestamp(
                        mtime, tz=timezone.utc
                    ).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "size": md_file.stat().st_size,
                    "title": extract_title(md_file),
                })

    return results


def build_manifest(sources: list[dict], mode: str) -> dict:
    """Build the output manifest from collected sources."""
    by_type: dict[str, int] = {}
    by_user: dict[str, int] = {}
    for s in sources:
        by_type[s["type"]] = by_type.get(s["type"], 0) + 1
        by_user[s["user"]] = by_user.get(s["user"], 0) + 1

    return {
        "last_compile": get_last_compile_iso(),
        "scan_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "mode": mode,
        "sources": sources,
        "total_new": len(sources),
        "by_type": by_type,
        "by_user": by_user,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List source files for wiki compilation."
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Ignore .last_compile, return all sources.",
    )
    parser.add_argument(
        "--touch",
        action="store_true",
        help="Update .last_compile after outputting manifest.",
    )
    parser.add_argument(
        "--type",
        dest="type_filter",
        choices=["progress", "handoff-active", "handoff-completed", "plan", "research"],
        help="Filter to a specific source type.",
    )
    parser.add_argument(
        "--since",
        help="Override since-date (YYYY-MM-DD). Takes precedence over .last_compile.",
    )

    args = parser.parse_args()

    # Determine the cutoff timestamp
    if args.full:
        since = 0.0
        mode = "full"
    elif args.since:
        try:
            dt = datetime.strptime(args.since, "%Y-%m-%d").replace(
                tzinfo=timezone.utc
            )
            since = dt.timestamp()
            mode = f"since:{args.since}"
        except ValueError:
            print(f"ERROR: Invalid date format: {args.since} (expected YYYY-MM-DD)",
                  file=sys.stderr)
            return 1
    else:
        since = get_last_compile()
        mode = "incremental"

    sources = scan_sources(since, args.type_filter)
    manifest = build_manifest(sources, mode)

    json.dump(manifest, sys.stdout, indent=2)
    print()

    if args.touch:
        touch_last_compile()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
