---
name: loop-me
description: Grill me about specs for the workflows I want to build, within this workspace.
disable-model-invocation: true
argument-hint: "A workflow to design, or nothing to go find one"
---

Run a stateful `/grilling` session whose only output is **workflow** specs. Use the grilling discipline — relentless, a round of questions at a time, a recommended answer attached to each — aimed at the vocabulary and goal below. For Rio implementation work, capture the outcome through `/spec` in `docs/specs/NNN-<slug>.md` and continue with `/plan`; preserve existing specs and record supersession instead of deleting decisions.

## The loop lens

A **loop** is a recurring pattern in the user's life: their career, their week, their morning, a single repeated activity. Picturing a life as loops within loops reveals how predictable its activities really are — which is what makes them worth **delegating**. Use the lens to find loops worth specifying, and propose ones the user hasn't noticed.

A **workflow** is the spec of one loop, made real. You run a workflow on a loop — the loop is its running instantiation. Rio workflow specifications live in `docs/specs/NNN-<slug>.md`. A separate personal workflow workspace may use `workflows/*.md` when the user explicitly selects it.

## Vocabulary

A shared language, reached for only when a workflow calls for it — never a checklist. **Mandate nothing structural**: a workflow needs no AI, no checkpoint, and no schedule unless the grilling shows it does.

- **Trigger** — what fires each run: an **event** (a new email, a new issue) or a **schedule** (every morning). Event-triggering is usually the more efficient.
- **Checkpoint** — a human-in-the-loop point where the user is asked to verify or decide. Some workflows have none and run autonomously; some use no AI at all.
- **Push right** — defer the checkpoint as far as it will go. Do maximal work before involving the human, so they are asked once, late, with everything prepared.
- **Brief** — what a checkpoint presents: a tight, decision-ready summary — what was produced, why, and a link down to the asset itself — never the raw output. The user reads a brief, not a draft. Speed of review is imperative.

## Definition of done

A workflow spec is done when an implementer agent could build it without asking a single question. Grill until then; nothing is done while a question remains.

## The workspace

- In Rio, use the relevant factory spec and `docs/research` for supporting evidence. Do not create a competing root-level spec or notes system.
- In an explicitly selected personal workflow workspace, use `workflows/*.md` and `NOTES.md` for its workflows and vocabulary. Record only information relevant to the requested workflow.
