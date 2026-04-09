# Session Persistence Schema

Convention for skills that need to persist state between sessions.

---

## File Location

```
.claude/skills/<skill-name>/state/<purpose>.yaml
```

Example: `.claude/skills/project-wiki/state/lint-results.yaml`

## Required Fields

Every state file must include:

```yaml
last_updated: "2026-04-09T14:30:00Z"  # ISO 8601
session_id: "abc123"                    # Session that last wrote this file
```

## Guidelines

- **YAML not JSON** — human-readable diffs, supports comments
- **No secrets** — state files may be committed; use environment variables for credentials
- **Gitignore in app repos** — add `.claude/skills/*/state/` to `.gitignore` in application repos (governance repos may track state)
- **Atomic writes** — write to a temp file then `mv` to avoid partial reads
- **Size cap** — state files should stay under 50 lines; if larger, split by purpose
