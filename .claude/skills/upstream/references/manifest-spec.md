# Archetype Manifest Specification

## File: `.archetype-manifest.json`

Must exist at the root of any instance repo before `/upstream` can work.

## Schema

```json
{
  "archetype_origin": "/path/to/root-archetype",
  "template_values": {
    "PROJECT_NAME": "my-project",
    "PROJECT_ROOT": "/path/to/my-project"
  },
  "portable_paths": [
    "scripts/",
    "agents/",
    "swarm/",
    ".claude/skills/",
    "scripts/hooks/",
    ".claude/commands/"
  ],
  "templated_files": [
    "CLAUDE.md",
    "README.md",
    "SPEC.md",
    "nightshift.yaml"
  ]
}
```

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `archetype_origin` | string | Absolute path to the archetype repo this instance was seeded from |
| `template_values` | object | Key-value pairs used during init. Keys match `{{PLACEHOLDER}}` names in templated files |
| `portable_paths` | string[] | Directories/files copied verbatim from archetype. These are diffed during upstream |
| `templated_files` | string[] | Files where `{{PLACEHOLDERS}}` were replaced during init. These get reverse-templated during upstream |

## Reverse-templating

During upstream, `distill.sh` replaces concrete values back to placeholders:

```
"my-project" → "{{PROJECT_NAME}}"
"/path/to/my-project" → "{{PROJECT_ROOT}}"
```

This uses `sed` substitution, which means project names containing regex metacharacters (`.`, `+`, `*`, `[`, `]`, `(`, `)`, `{`, `}`, `\`) will break silently.

## Creating the manifest

For instances created before the manifest system:
```bash
scripts/upstream/retroactive-manifest.sh
```

This scans the repo to infer template values and portable paths from the archetype's known structure.
