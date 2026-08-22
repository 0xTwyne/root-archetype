# Skill Description Formula

The `description` field in YAML frontmatter is the single most important line in a skill. It's NOT a summary — it's what Claude scans to decide "is there a skill for this request?"

## Formula

```
[What it does] + [When to use it — keywords/phrases] + [When NOT to use it]
```

## Good examples

```yaml
description: Commit changes with staged-diff secret scanning and branch protection guardrails. Use when user says "safe commit", "safe-commit", or "commit with checks". Do NOT use for regular commits — this is an opt-in extra layer on top of normal git workflow.
```

```yaml
description: Scaffold a new Claude Code skill with correct folder structure, YAML frontmatter, gotchas section, and progressive disclosure. Use when user says "create a skill", "new skill", "scaffold skill", "add a skill". Do NOT use when user wants to edit an existing skill.
```

```yaml
description: Manages cross-repo handoff lifecycle including creation, status updates, and archival. Use when user mentions "handoff", "work item", "cross-repo task", or asks to track work across repositories.
```

## Bad examples

```yaml
# Too vague — Claude can't decide when to trigger
description: Helps with handoffs.

# No trigger phrases — Claude doesn't know what user words activate it
description: A tool for managing work items across repositories.

# Too broad — will overtrigger on unrelated requests
description: Use for anything related to git or code changes.
```

## Rules

- Under 1024 characters
- No XML angle brackets (`<`, `>`)
- Must contain "Use when" or "Trigger when" phrase
- Should include specific keywords users would say
- Should include negative triggers ("Do NOT use when") to prevent overtriggering
- Enumerate actual trigger words in quotes when possible
