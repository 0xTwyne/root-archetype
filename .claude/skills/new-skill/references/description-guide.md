# Skill Description Formula

The `description` field in YAML frontmatter is the single most important line in a skill. It's NOT a summary — it's what Claude scans to decide "is there a skill for this request?"

## Formula

```
[What it does] + [When to use it — keywords/phrases] + [When NOT to use it]
```

## Good examples

```yaml
description: Launch and manage multi-agent swarm coordination for parallel work. Use when user mentions "swarm", "parallel agents", "workers", "work queue", or asks to coordinate multiple agents on a task. Do NOT use for general concurrency questions unrelated to this project's swarm primitive.
```

```yaml
description: Discover and install agent skills from the open ecosystem. Use when user asks "how do I do X", "find a skill for X", "is there a skill that can...", or expresses interest in extending capabilities. Do NOT use when user asks about already-installed skills.
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
