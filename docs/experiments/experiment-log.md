# RISC-V Interpreter — Experiment Log (Index)

One entry per **open question**, not per combination tried. When a question
is answered, mark it Closed here and stop revisiting it. New questions get
their own file, appended to this index — don't retrofit them into old ones.

Workload target: general desktop-ish (Linux kernel, Doom), RV64GC.

Each question is one of three types — the type determines what counts as a
valid result. See `_template.md`(or `_template_decision.md`) for the full rules on each.

- **[DESIGN]** — no correct baseline exists yet. Comparing candidates to
  choose the first real implementation. Correctness checked for every
  candidate; the winner is merged directly as the implementation.
- **[OPTIMIZATION]** — a correct baseline exists. Testing whether a change
  makes it faster without breaking it. Correctness gated before any perf
  number is recorded.
- **[DECISION]** — no correct baseline exists yet. To be used when reasoning
  about choices and trade-offs without real meeasurable properties.

New question → copy `_template.md`(or `_template_decision.md`) to 
`qN-short-slug.md`, fill in Why/Hypothesis/What's varied *before* 
running anything, add a row below.

---

## Open

| # | Type | Question | File |
|---|------|----------|------|

---

## Closed

Newest first. One-line verdict only — full reasoning lives in the file.

| # | Type | Question | Verdict | File |
|---|------|----------|---------|------|
| 1 | [DECISION] | Should we use `minisign` for bootstrapping scripts? | Don't use `minisign`, add hardcoded hashes | [q1-bootstrapping-scripts.md](./q1-bootstrapping-scripts.md) |
