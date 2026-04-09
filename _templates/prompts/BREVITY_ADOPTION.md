# Brevity Template Adoption Guide

## Overview

These templates provide format-specific word limits for LLM worker prompts. Research (CCoT arXiv:2407.19825, TALE arXiv:2412.18547) shows explicit numeric limits outperform vague "be concise" instructions.

## Templates

| Template | Purpose | Key Limits |
|----------|---------|------------|
| `worker_general.md.template` | General Q&A worker | MC: 1 sentence, factual: <15w, open: <60w |
| `worker_math.md.template` | Math/reasoning worker | MC: 1 sentence, numeric: <50w, proof: <100w |
| `thinking_reasoning.md.template` | Extended thinking suffix | Answer: <50w |

## How to Adopt

1. Copy the relevant templates to your project's `orchestration/prompts/roles/` directory
2. Remove the `.template` suffix
3. Customize word limits based on your accuracy requirements:
   - Tighter limits (fewer words) → lower token cost, may lose accuracy on complex tasks
   - Looser limits (more words) → higher token cost, better accuracy on nuanced answers
4. Test with your evaluation suite before deploying

## Key Principles

1. **Format-specific limits** beat blanket "be concise" — different question types need different budgets
2. **"No preamble. No restating the question."** eliminates the most common waste pattern
3. **Lead with the answer** — put the key insight first, explanation second
4. **Never suppress reasoning** — say "be concise" (stylistic), never "don't think about X" (content suppression)

## Research Basis

- CCoT (arXiv:2407.19825): 30-60 word sweet spot for answer portions
- TALE (arXiv:2412.18547): Self-estimated budgets can outperform static limits
- OpenAI CoT Controllability (arXiv:2603.05706): Stylistic control has ≤2.7pp accuracy cost; content suppression has 6-16.7pp cost
