#!/usr/bin/env python3
"""Query the project knowledge base for compiled knowledge on a topic.

Pre-filters intake_index.yaml and scans handoffs/deep-dives to reduce
context for LLM synthesis. Returns JSON with matching entries.

Usage:
    python3 query_wiki.py "speculative decoding"
    python3 query_wiki.py "knowledge base" --category knowledge_management
    python3 query_wiki.py "KV cache" --max-results 10
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[4]  # epyc-root


def load_wiki_config() -> dict:
    wiki_path = ROOT / "wiki.yaml"
    if wiki_path.exists():
        with open(wiki_path) as f:
            return yaml.safe_load(f) or {}
    return {}


def _match_score(query_terms: list[str], text: str) -> int:
    """Score how well query terms match a text. Higher = better match."""
    if not text:
        return 0
    text_lower = text.lower()
    score = 0
    for term in query_terms:
        if term in text_lower:
            score += 1
            # Bonus for exact phrase match
            if len(term.split()) > 1 and term in text_lower:
                score += 2
    return score


def search_intake(index_path: Path, query_terms: list[str],
                  category_filter: str | None, max_results: int) -> list[dict]:
    """Search intake index for matching entries."""
    if not index_path.exists():
        return []

    with open(index_path) as f:
        entries = yaml.safe_load(f)
    if not isinstance(entries, list):
        entries = entries.get("entries", []) if isinstance(entries, dict) else []

    scored = []
    for entry in entries:
        # Category filter
        if category_filter:
            cats = entry.get("categories", [])
            if category_filter not in cats:
                continue

        # Score across searchable fields
        def _safe_join(items: list) -> str:
            return " ".join(str(x) for x in items if x)

        score = 0
        score += _match_score(query_terms, entry.get("title", "")) * 3
        score += _match_score(query_terms, _safe_join(entry.get("categories", []))) * 2
        score += _match_score(query_terms, _safe_join(entry.get("techniques", []))) * 2
        score += _match_score(query_terms, _safe_join(entry.get("key_claims", [])))
        score += _match_score(query_terms, str(entry.get("notes", "")))

        if score > 0:
            # Return a trimmed version (no bulky notes field in output)
            trimmed = {
                "id": entry.get("id"),
                "title": entry.get("title"),
                "categories": entry.get("categories"),
                "verdict": entry.get("verdict"),
                "relevance": entry.get("relevance"),
                "novelty": entry.get("novelty"),
                "key_claims": entry.get("key_claims", [])[:3],
                "techniques": entry.get("techniques", []),
                "handoffs_created": entry.get("handoffs_created"),
                "handoffs_updated": entry.get("handoffs_updated"),
                "ingested_date": entry.get("ingested_date"),
                "_score": score,
            }
            scored.append(trimmed)

    # Sort by score descending
    scored.sort(key=lambda x: x["_score"], reverse=True)
    return scored[:max_results]


def search_handoffs(handoff_dirs: list[Path], query_terms: list[str],
                    max_results: int) -> list[dict]:
    """Search handoff files for matching content."""
    results = []

    for hdir in handoff_dirs:
        if not hdir.exists():
            continue
        for md_file in sorted(hdir.glob("*.md")):
            content = md_file.read_text(errors="replace")
            # Score based on filename + first 200 chars (title/status) + full content
            score = 0
            name_text = md_file.stem.replace("-", " ")
            score += _match_score(query_terms, name_text) * 3
            score += _match_score(query_terms, content[:500]) * 2
            score += _match_score(query_terms, content)

            if score > 0:
                # Extract status line
                status_match = re.search(r'\*\*Status\*\*:\s*(.+)', content)
                status = status_match.group(1).strip() if status_match else "unknown"
                # Extract title (first H1)
                title_match = re.search(r'^#\s+(.+)', content, re.MULTILINE)
                title = title_match.group(1).strip() if title_match else md_file.stem

                results.append({
                    "file": md_file.name,
                    "directory": hdir.name,
                    "title": title,
                    "status": status[:80],
                    "_score": score,
                })

    results.sort(key=lambda x: x["_score"], reverse=True)
    return results[:max_results]


def search_deep_dives(deep_dive_dir: Path, query_terms: list[str],
                      max_results: int) -> list[dict]:
    """Search deep-dive files for matching content."""
    results = []
    if not deep_dive_dir.exists():
        return results

    for md_file in sorted(deep_dive_dir.glob("*.md")):
        content = md_file.read_text(errors="replace")
        name_text = md_file.stem.replace("-", " ")
        score = _match_score(query_terms, name_text) * 3
        score += _match_score(query_terms, content[:500]) * 2
        score += _match_score(query_terms, content)

        if score > 0:
            title_match = re.search(r'^#\s+(.+)', content, re.MULTILINE)
            title = title_match.group(1).strip() if title_match else md_file.stem
            results.append({
                "file": md_file.name,
                "title": title,
                "_score": score,
            })

    results.sort(key=lambda x: x["_score"], reverse=True)
    return results[:max_results]


def main() -> int:
    parser = argparse.ArgumentParser(description="Query the project knowledge base")
    parser.add_argument("query", help="Search query (keywords or phrase)")
    parser.add_argument("--category", "-c", help="Filter by category")
    parser.add_argument("--max-results", "-n", type=int, default=15,
                        help="Maximum results per source (default: 15)")
    parser.add_argument("--json", action="store_true", default=True,
                        help="Output as JSON (default)")
    parser.add_argument("--human", action="store_true",
                        help="Output in human-readable format")
    args = parser.parse_args()

    config = load_wiki_config()
    query_terms = [t.lower() for t in args.query.split() if len(t) > 1]

    # Resolve paths
    index_path = ROOT / config.get("cross_references", {}).get("intake_index",
        "research/intake_index.yaml")
    handoff_paths_cfg = config.get("cross_references", {}).get("handoffs", {}).get("paths",
        ["handoffs/active", "handoffs/completed"])
    handoff_dirs = [ROOT / p if not Path(p).is_absolute() else Path(p)
                    for p in handoff_paths_cfg]
    deep_dive_rel = config.get("cross_references", {}).get("deep_dives", {}).get("path",
        "research/deep-dives")
    deep_dive_dir = ROOT / deep_dive_rel

    # Search
    intake_matches = search_intake(index_path, query_terms, args.category, args.max_results)
    handoff_matches = search_handoffs(handoff_dirs, query_terms, args.max_results)
    deep_dive_matches = search_deep_dives(deep_dive_dir, query_terms, args.max_results)

    result = {
        "query": args.query,
        "category_filter": args.category,
        "intake_matches": intake_matches,
        "handoff_matches": handoff_matches,
        "deep_dive_matches": deep_dive_matches,
        "totals": {
            "intake": len(intake_matches),
            "handoffs": len(handoff_matches),
            "deep_dives": len(deep_dive_matches),
        },
    }

    if args.human:
        print(f"Query: {args.query}")
        if args.category:
            print(f"Category filter: {args.category}")
        print()

        if intake_matches:
            print(f"### Intake Entries ({len(intake_matches)} matches)")
            for m in intake_matches:
                print(f"  [{m['id']}] {m['title'][:70]}")
                print(f"    verdict={m['verdict']}, relevance={m['relevance']}, score={m['_score']}")
            print()

        if handoff_matches:
            print(f"### Handoffs ({len(handoff_matches)} matches)")
            for m in handoff_matches:
                print(f"  [{m['directory']}/{m['file']}] {m['title'][:60]}")
                print(f"    status: {m['status'][:60]}, score={m['_score']}")
            print()

        if deep_dive_matches:
            print(f"### Deep Dives ({len(deep_dive_matches)} matches)")
            for m in deep_dive_matches:
                print(f"  [{m['file']}] {m['title'][:60]}")
            print()

        total = sum(result["totals"].values())
        print(f"Total: {total} results across {len([v for v in result['totals'].values() if v > 0])} sources")
    else:
        json.dump(result, sys.stdout, indent=2, default=str)
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
