# RISC-V Interpreter — Experiment Log (Index)

One entry per **open question**, not per combination tried. When a question
is answered, mark it Closed here and stop revisiting it. New questions get
their own file, appended to this index — don't retrofit them into old ones.

Workload target: general desktop-ish (Linux kernel, Doom), RV64GC.

Each question is one of two types — the type determines what counts as a
valid result. See `_template.md` for the full rules on each.

- **[DESIGN]** — no correct baseline exists yet. Comparing candidates to
  choose the first real implementation. Correctness checked for every
  candidate; the winner is merged directly as the implementation.
- **[OPTIMIZATION]** — a correct baseline exists. Testing whether a change
  makes it faster without breaking it. Correctness gated before any perf
  number is recorded.

New question → copy `_template.md` to `qN-short-slug.md`, fill in Why/
Hypothesis/What's varied *before* running anything, add a row below.

---

## Open

| # | Type | Question | File |
|---|------|----------|------|

---

## Closed

Newest first. One-line verdict only — full reasoning lives in the file.

*(none yet)*

| # | Type | Question | Verdict | File |
|---|------|----------|---------|------|
