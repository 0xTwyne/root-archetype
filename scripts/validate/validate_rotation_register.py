#!/usr/bin/env python3
"""Validate the credential rotation register (docs/rotation-register.json).

The register is the inventory of every Tier-1 and Tier-2 credential: who owns
it, where the keystore holds it, where resolved copies of it live, and when it
was last rotated. It holds references and metadata only -- never a value.

Checks (each one fails the run):
- the register exists and is valid JSON with the expected top-level keys
- every credential has the required fields, a known tier, and a store
  locator of the form <backend>:<locator> (not a URL, not a raw value)
- rotation_days does not exceed the policy maximum for the tier
- last_rotated is a real date, not in the future, and not overdue
- an upstream expiry (expires) has not passed
- every temporary grant has an expiry, the expiry has not passed, and the
  grant is no longer than policy.max_grant_days
- no string anywhere in the register matches a secret pattern from
  scripts/hooks/lib/secret-patterns.txt

Entries due within policy.due_soon_days print a WARN line but do not fail.
Output names entries by id only; it never prints a store locator or a value.

Usage:
    python3 scripts/validate/validate_rotation_register.py
        [--register PATH] [--today YYYY-MM-DD]

--today exists so tests are deterministic; normal runs use the current date.
"""

import json
import re
import sys
from datetime import date, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REGISTER = REPO_ROOT / "docs" / "rotation-register.json"
PATTERNS_FILE = REPO_ROOT / "scripts" / "hooks" / "lib" / "secret-patterns.txt"

# Defaults apply when the register's "policy" block leaves a key out.
DEFAULT_POLICY = {
    "max_rotation_days": {"1": 90, "2": 180},
    "max_grant_days": 30,
    "due_soon_days": 14,
}

CREDENTIAL_FIELDS = ["id", "tier", "owner", "store", "consumers", "copies",
                     "rotation_days", "last_rotated", "procedure"]
GRANT_FIELDS = ["id", "owner", "scope", "granted", "expires"]

# <backend>:<locator>, e.g. op://vault/item/field, sops:path#KEY, aws-sm:name.
# http(s) is refused: a URL in this slot is how provider keys leak.
STORE_RE = re.compile(r"^(?!https?:)[a-z][a-z0-9+.-]*:\S+$")


def load_patterns() -> list:
    """Return compiled regexes from secret-patterns.txt (label<TAB>regex<TAB>repl)."""
    patterns = []
    if not PATTERNS_FILE.exists():
        return patterns
    for line in PATTERNS_FILE.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        try:
            patterns.append((parts[0], re.compile(parts[1])))
        except re.error:
            continue
    return patterns


def walk_strings(node, path="$"):
    """Yield (json_path, string) for every string in a JSON structure."""
    if isinstance(node, str):
        yield path, node
    elif isinstance(node, dict):
        for k, v in node.items():
            yield from walk_strings(k, f"{path}.<key>")
            yield from walk_strings(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk_strings(v, f"{path}[{i}]")


def parse_date(value):
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def validate(register_path: Path, today: date) -> tuple:
    errors, warnings = [], []

    if not register_path.exists():
        return [f"register not found: {register_path} "
                "(see docs/guides/secrets-policy.md)"], warnings
    try:
        data = json.loads(register_path.read_text())
    except json.JSONDecodeError as exc:
        return [f"register is not valid JSON: {exc}"], warnings
    if not isinstance(data, dict):
        return ["register top level must be an object"], warnings

    for key in ("credentials", "temporary_grants"):
        if not isinstance(data.get(key), list):
            errors.append(f"'{key}' must be a list")
    if errors:
        return errors, warnings

    policy = dict(DEFAULT_POLICY)
    policy.update(data.get("policy") or {})
    max_days = {str(k): v for k, v in policy["max_rotation_days"].items()}
    soon = timedelta(days=int(policy["due_soon_days"]))

    # A value pasted anywhere in the register fails, whatever the field.
    for label, rx in load_patterns():
        for jpath, s in walk_strings(data):
            if rx.search(s):
                errors.append(f"{jpath}: matches secret pattern '{label}' "
                              "-- the register holds references, never values")

    seen = set()
    for i, cred in enumerate(data["credentials"]):
        if not isinstance(cred, dict):
            errors.append(f"credentials[{i}]: must be an object")
            continue
        cid = cred.get("id") or f"credentials[{i}]"
        missing = [f for f in CREDENTIAL_FIELDS if f not in cred]
        if missing:
            errors.append(f"{cid}: missing field(s) {', '.join(missing)}")
            continue
        if cid in seen:
            errors.append(f"{cid}: duplicate id")
        seen.add(cid)

        tier = str(cred["tier"])
        if tier not in ("1", "2", "3"):
            errors.append(f"{cid}: tier must be 1, 2 or 3 (got {cred['tier']!r})")
            continue
        if not isinstance(cred["store"], str) or not STORE_RE.match(cred["store"]):
            errors.append(f"{cid}: store must be a keystore locator "
                          "'<backend>:<locator>', not a URL or a value")
        for list_field in ("consumers", "copies"):
            if not isinstance(cred[list_field], list):
                errors.append(f"{cid}: {list_field} must be a list ([] if none)")
        if not str(cred["owner"]).strip():
            errors.append(f"{cid}: owner is empty")

        if tier == "3":
            continue  # config, not a credential: no rotation clock

        rdays = cred["rotation_days"]
        if not isinstance(rdays, int) or rdays <= 0:
            errors.append(f"{cid}: rotation_days must be a positive integer")
            continue
        limit = max_days.get(tier)
        if limit is not None and rdays > int(limit):
            errors.append(f"{cid}: rotation_days {rdays} exceeds the "
                          f"Tier-{tier} maximum of {limit}")

        last = parse_date(cred["last_rotated"])
        if last is None:
            errors.append(f"{cid}: last_rotated must be YYYY-MM-DD")
            continue
        if last > today:
            errors.append(f"{cid}: last_rotated {last} is in the future")
        due = last + timedelta(days=rdays)
        if today > due:
            errors.append(f"{cid}: rotation OVERDUE since {due} "
                          f"(last rotated {last}, every {rdays} days)")
        elif today >= due - soon:
            warnings.append(f"{cid}: rotation due {due}")

        if "expires" in cred and cred["expires"] not in (None, ""):
            exp = parse_date(cred["expires"])
            if exp is None:
                errors.append(f"{cid}: expires must be YYYY-MM-DD")
            elif today > exp:
                errors.append(f"{cid}: upstream credential EXPIRED on {exp}")
            elif today >= exp - soon:
                warnings.append(f"{cid}: upstream credential expires {exp}")

    max_grant = int(policy["max_grant_days"])
    for i, grant in enumerate(data["temporary_grants"]):
        if not isinstance(grant, dict):
            errors.append(f"temporary_grants[{i}]: must be an object")
            continue
        gid = grant.get("id") or f"temporary_grants[{i}]"
        missing = [f for f in GRANT_FIELDS if not grant.get(f)]
        if missing:
            errors.append(f"grant {gid}: missing field(s) {', '.join(missing)}")
            continue
        start, end = parse_date(grant["granted"]), parse_date(grant["expires"])
        if start is None or end is None:
            errors.append(f"grant {gid}: granted/expires must be YYYY-MM-DD")
            continue
        if (end - start).days > max_grant:
            errors.append(f"grant {gid}: lasts {(end - start).days} days, "
                          f"maximum is {max_grant}")
        if today > end:
            errors.append(f"grant {gid}: EXPIRED on {end} -- revoke it upstream "
                          "and remove the entry, or renew it with a new expiry")
        elif today >= end - soon:
            warnings.append(f"grant {gid}: expires {end}")

    return errors, warnings


def main(argv: list) -> int:
    register, today = DEFAULT_REGISTER, date.today()
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--register" and args:
            register = Path(args.pop(0))
        elif arg == "--today" and args:
            parsed = parse_date(args.pop(0))
            if parsed is None:
                print("ERROR: --today must be YYYY-MM-DD", file=sys.stderr)
                return 2
            today = parsed
        else:
            print("usage: validate_rotation_register.py "
                  "[--register PATH] [--today YYYY-MM-DD]", file=sys.stderr)
            return 2

    errors, warnings = validate(register, today)
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"FAIL  {e}")
    if errors:
        print(f"Rotation register: {len(errors)} error(s)")
        return 1
    print(f"Rotation register OK ({today})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
