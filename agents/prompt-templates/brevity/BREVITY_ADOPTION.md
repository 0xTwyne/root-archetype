# Brevity Template Adoption

These templates are starter snippets for projects that want shorter model
responses without losing verifiability. `init-project.sh` copies them to
`local/prompt-templates/brevity/` so each project can adapt them without
editing tracked archetype files.

## Recommended Use

1. Pick one role or benchmark slice first.
2. Add the relevant snippet as a prompt suffix or role overlay.
3. Measure accuracy, refusal/clarification rate, and answer length before and after.
4. Keep the template only if quality is stable and the shorter output improves the workflow.

## Do Not Use When

- The task requires a full audit trail.
- The user explicitly asks for detailed explanation.
- Safety, legal, medical, financial, or security context needs caveats.
- The model is already under-answering or skipping verification steps.
