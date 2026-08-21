# /wrap-up — moved

The wrap-up methodology now lives at `agents/skills/wrap-up/SKILL.md`, discovered
by Claude Code through the generated wrapper in `.claude/skills/wrap-up/`.

This file previously held a separate "Mid-Session Save & Wiki Compile" variant.
Two competing wrap-ups was a source of drift — they disagreed about where the
wiki lives and which indexes get rebuilt — so it has been retired in favour of
the single skill.

Read `agents/skills/wrap-up/SKILL.md`.

The skill is safe to run mid-session, not only at the end: it checkpoints
progress, rebuilds indexes, and pushes. That was the one genuinely useful idea
in the old variant, and it is preserved there.
