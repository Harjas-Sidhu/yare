# Q4: [DESIGN] Which interpreter dispatch mechanism is the working baseline for the RV64GC interpreter?

**Status:** Closed
**Date opened:** 2026-08-15
**Date closed:** 2026-09-04
**Baseline:** Tailcall dispatch

## Why this question

Dispatch is paid once per decoded instruction, making it one of the highest-leverage
fixed costs in the interpreter.

Several dispatch mechanisms are viable, but their performance depends on both the
generated control flow and the host CPU's branch prediction. This [DESIGN] compares
the candidate mechanisms before the RV64GC interpreter is built on top of one of them.

The experiment is intentionally isolated from instruction decoding and execution.

It establishes a working baseline for the interpreter, but does not attempt to
determine which mechanism is universally best or how the mechanisms behave on
real RV64GC instruction traces.

## Hypothesis

A dispatch mechanism with a separate dispatch site for each instruction kind should
outperform mechanisms using one shared dispatch site, because the host branch
predictor gets more specific prediction sites.

Among the per-site mechanisms, tailcall dispatch is expected to be fastest because
it transfers directly from one handler to the next without a call/return pair.

Context threading is expected to be competitive because its ordinary call/return pairs
can use the CPU's return-address predictor.

The relative performance of tailcall and context threading is expected to depend on
the predictability of the instruction sequence.

## What's held fixed

* Same host machine: AMD Ryzen 7 5800H, 16 threads, `powersave` governor.
* Same toolchain, build flags, and benchmark harness across every variant.
* Build configuration: `-O ReleaseFast -fomit-frame-pointer`.
* Identical semantics for identical instruction sequences.
* Four fixed workloads: arithmetic, memory, mixed, and stack.
* One synthetic instruction stream with predictability varied from 0%, 25%, 50%,
  75%, and 100%.
* Fixed workloads use 2,000,000 iterations each.
* Stream workloads use the same instruction sequences across every variant.
* No instruction decoding or execution work is included in the dispatch comparison.

The harness is independent of the RV64GC decoder and exists only to isolate dispatch
behavior.

## What's varied

| Variant           | Description                                                                       |
| ----------------- | --------------------------------------------------------------------------------- |
| switch            | One shared dispatch site for every instruction kind                               |
| indirect_call     | One shared dispatch site using an indirect call                                   |
| tailcall          | One dispatch site per instruction kind, transferring via indirect jump            |
| context_threading | One dispatch site per instruction kind, using an ordinary direct call/return pair |

## Correctness check

Every candidate must produce the expected checksum before any performance number is
recorded.

The fixed workloads are checked against a reference implementation. The synthetic
stream has no independent reference implementation, so its checksum is compared
across all variants.

| Variant           | Correctness result |
| ----------------- | ------------------ |
| switch            | Pass               |
| indirect_call     | Pass               |
| tailcall          | Pass               |
| context_threading | Pass               |

No checksum mismatches were observed across any workload or predictability level.

## Method

Each workload/variant combination was run for 10 trials.

Wall time is reported as the median across trials. IPC and branch-miss rate are
reported as the mean across trials using hardware performance counters.

The fixed workloads execute 2,000,000 iterations. The synthetic stream is evaluated
at five predictability levels from 0% to 100%.

Because source-level dispatch structure does not necessarily correspond to the
generated control flow, the `tailcall` and `context_threading` implementations were
also disassembled for the exact benchmark build
(`-O ReleaseFast -fomit-frame-pointer`).

This verifies that the measured variants retain the intended dispatch mechanisms.

In addition, `perf report` was used to capture the per-opcode-handler sample
distribution for every workload/variant combination. This allows differences between
workloads to be compared against their actual instruction-mix composition rather
than inferred from aggregate counters alone.

## Result

### Fixed workloads

| Workload   | Variant           | Median wall time |  IPC | Branch-miss rate |
| ---------- | ----------------- | ---------------: | ---: | ---------------: |
| arithmetic | indirect_call     |         158.3 ms | 1.55 |            1.55% |
| arithmetic | tailcall          |      **58.3 ms** | 2.87 |            0.03% |
| arithmetic | context_threading |          95.1 ms | 2.19 |            0.00% |
| memory     | indirect_call     |         270.1 ms | 1.37 |            2.20% |
| memory     | tailcall          |      **84.0 ms** | 2.36 |            0.06% |
| memory     | context_threading |         133.5 ms | 2.16 |            0.10% |
| mixed      | indirect_call     |         241.0 ms | 1.35 |            2.52% |
| mixed      | tailcall          |      **98.8 ms** | 1.56 |           10.24% |
| mixed      | context_threading |         120.3 ms | 2.10 |            0.35% |
| stack      | indirect_call     |         194.1 ms | 1.70 |            1.06% |
| stack      | tailcall          |         138.3 ms | 1.26 |           19.13% |
| stack      | context_threading |     **110.8 ms** | 2.11 |            0.23% |

Tailcall is fastest on three of the four fixed workloads. Context threading wins only
on `stack`.

### Predictability sweep

| Predictability | switch | indirect_call | tailcall | context_threading |
| -------------- | -----: | ------------: | -------: | ----------------: |
| 0%             |  10.94 |         10.97 |     7.60 |              7.60 |
| 25%            |  10.98 |         10.82 | **7.18** |              7.29 |
| 50%            |  10.38 |         10.63 | **6.30** |              6.71 |
| 75%            |   8.92 |         10.08 | **4.78** |              5.00 |
| 100%           |   2.96 |          6.52 | **1.27** |              2.13 |

Values are nanoseconds per instruction.

Tailcall is fastest at every predictability level.

At 0% predictability, tailcall and context threading are effectively tied on median
wall time, with both rounding to 7.609 ns/instruction across trials. At 100%
predictability, tailcall is approximately `1.7x` faster.

The synthetic stream's opcode alphabet is a near-uniform mix of ~22 arithmetic,
memory, and stack opcodes, with `tPush`/`tPop` making up no more than ~4% of samples
combined at any predictability level. The sweep therefore characterizes dispatch
behavior as a function of sequence predictability under a broad, evenly distributed
opcode mix.

It does not by itself characterize workloads whose opcode mix is concentrated on a
small subset of handlers, which is the situation observed in `stack`.

### `stack` reversal

Disassembly of the exact no-frame-pointer build confirms that the `stack` result is
not caused by tailcall being compiled into a different mechanism.

All tailcall handlers end in an indirect jump:

```asm
jmp qword ptr [8*rax + table]
```

with no `call`/`ret` pair in the dispatch path.

Context threading instead contains distinct direct call sites for each opcode,
selected through a jump table. The selected handler therefore executes through an
ordinary call/return pair.

The reversal is consequently a behavioral effect of the generated control flow
rather than a code-generation failure.

Branch density alone does not explain it. Tailcall has nearly identical branch
density on `mixed` and `stack` (1.13 and 1.11 branches per instruction), but `stack`
produces substantially more absolute mispredictions:

| Workload | Instructions | Branch mispredicts |
| -------- | -----------: | -----------------: |
| mixed    |         ~52M |              6.01M |
| stack    |         ~50M |             10.65M |

Per-opcode `perf report` profiling identifies a corresponding difference in
instruction-mix concentration: `stack` is dominated by `tPush`/`tPop`, which together
account for 44% of sampled cycles in the tailcall build, versus 0% in `arithmetic`,
`memory`, and `mixed`.

No other fixed workload concentrates this heavily on a small handler subset.
Branch/jump opcodes (`tJnz`/`tJmp`) are present at comparable, low single-digit
shares across all four fixed workloads, so their presence does not distinguish
`stack` from the others.

This concentration is consistent with the branch-miss data. Tailcall's branch-miss
rate on `stack` (19.13%) is nearly double its rate on `mixed` (10.24%) and far above
`arithmetic`/`memory` (0.03%/0.06%), while context threading remains low across all
four fixed workloads (0.00%-0.35%).

The measurements are consistent with a push/pop-heavy sequence being a harder case
for tailcall's indirect-jump prediction than for context threading's call/return
path. However, this experiment does not independently isolate predictor behavior
from all other effects of the concentrated opcode mix.

The `stack` result therefore demonstrates that opcode-mix concentration, not just
branch density or sequence predictability, can materially affect the relative
performance of tailcall and context threading.

Critically, the synthetic predictability stream does not reproduce or test this
effect: `tPush`/`tPop` combined never exceed ~4% of the stream's opcode mix at any
predictability level. The sweep's confirmation of tailcall's advantage should
therefore not be read as validating that advantage on push/pop-heavy or otherwise
handler-concentrated workloads.

## Verdict

**Tailcall becomes the working baseline for the RV64GC interpreter.**

It wins three of the four fixed workloads and the entire predictability sweep.

The one fixed workload where it loses, `stack`, has been verified to use the same
tailcall mechanism as the other workloads. Its reversal is strongly associated with
the workload's concentration on `tPush`/`tPop` and the corresponding increase in
branch mispredictions. The result is therefore treated as a genuine,
opcode-mix-dependent performance difference rather than an implementation defect.

This makes tailcall the strongest baseline for continuing interpreter development.

The result does not establish that tailcall will be fastest on real RV64GC workloads.
In particular, the `stack` workload demonstrates that concentrated opcode mixes can
change the relative performance of tailcall and context threading.

The choice should therefore be revisited if measurements on a real RV64GC trace show
materially different behavior. Such a trace should include per-opcode profiling via
`perf report`, rather than relying only on aggregate branch-density or IPC metrics.

## Follow-up questions raised

* [OPTIMIZATION]: Does context threading outperform the tailcall RV64GC
  interpreter on a real workload trace?

  Baseline: the tailcall RV64GC interpreter once it exists.

  This should be evaluated using a representative trace, such as Linux boot, and
  should include a per-opcode `perf report` breakdown to determine whether the trace's
  opcode mix is concentrated, as in `stack`, or broad, as in the other workloads.

* [UNCATEGORIZED, INTERNAL]: Does the measured behavior of context threading agree
  with expectations from prior work on threaded interpreters and host branch
  prediction?

  This is an interpretation question rather than a requirement for the interpreter
  and can remain deferred.
