<!--
Copy this file to qN-short-slug.md (e.g. q2-tlb-associativity.md).
Add a row to experiment-log.md's Open table pointing at it.
Fill in Why / Hypothesis / What's held fixed / What's varied BEFORE
running anything — that ordering is the entire point of this doc.
Delete this comment block once you start filling the file in.
-->

# QN: [DESIGN|OPTIMIZATION] <short question, phrased so it has a real answer>

**Status:** Open
**Date opened:**
**Date closed:**
**Baseline:** <"None yet — winner becomes the baseline" for DESIGN,
or a link/commit for OPTIMIZATION>

## Why this question
What prompted it, and why it matters for the actual goal (a specific
milestone), not just curiosity.

## Hypothesis
What you expect to happen and why — written *before* running anything.

## What's held fixed
Everything deliberately NOT varying, so the comparison stays clean
(host CPU, compiler flags, build mode, instruction trace, etc.)

## What's varied
2-4 candidates (DESIGN) or baseline + 1-3 modified variants
(OPTIMIZATION). Resist adding "just to see" variants — that's a new
question, give it its own file.

| Variant | Description |
|---|---|
| A | |
| B | |

## Correctness check
**DESIGN:** required for every candidate, not just the winner.
**OPTIMIZATION:** pass/fail gate before any perf number is recorded —
a variant that fails is discarded, not listed in Results.

| Variant | Correctness result |
|---|---|
| A | |
| B | |

## Method
How performance was measured: workload/trace, build mode
(Debug/ReleaseSafe/ReleaseFast), iterations, what's timed, what tool.

## Result

DESIGN:

| Variant | Metric | Value | Notes |
|---|---|---|---|
| A | | | |
| B | | | |

OPTIMIZATION (correctness-passing variants only):

| Variant | Metric | Value | Delta vs baseline | Notes |
|---|---|---|---|---|
| Baseline | | | — | |
| A | | | | |

## Verdict
Which candidate becomes/updates the implementation, and why — not just
"A was faster" but what it implies going forward.

## Follow-up questions raised
New questions this surfaced, each getting its own file. "None" if not
applicable.
