---
name: research
description: Research a market, user or UX question for this product and write the result to docs/research/<slug>.md. Use when a decision needs evidence before a spec.
argument-hint: "<question or topic>"
---

Research: $ARGUMENTS

1. Name the question in one sentence and the decision it serves. If no
   decision depends on it, say so and stop.
2. Check `docs/research` and `docs/adr` for prior work; build on it.
3. Delegate: market, pricing, competitors or user feedback → `researcher`;
   flows, screens, friction, first-use questions → `ux-researcher`. Both for a
   feature with a UI and a business case. Give each the question, the product
   context in two sentences, and the template at `docs/research/TEMPLATE.md`.
4. Merge into `docs/research/<slug>.md`: findings with sources and dates,
   what it means for the product, the decision it supports, what is unknown.
5. Report the file and the one-paragraph answer. No code changes.
