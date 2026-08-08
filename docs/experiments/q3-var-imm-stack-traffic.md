# Q3: [OPTIMIZATION] Does mutable `var imm: uN` accumulation cause stack traffic?

**Status:** Closed
**Date opened:** 2026-08-06
**Date closed:** 2026-08-08
**Baseline:** `decompress_j` using mutable `var imm: u12` accumulation

## Why this question

LLVM-generated assembly for `decompress` showed stores such as:

```asm
mov word ptr [rbp - N], <reg>
```

with no corresponding reload. These appeared in otherwise register-only,
branchless decode paths.

`decompress` is part of the emulator's hot instruction-fetch path, so even
unnecessary store-buffer traffic is worth investigating. More importantly,
the store suggested that the source-level accumulation pattern was inhibiting
optimization.

## Hypothesis

The stack traffic was expected to come from one of three causes:

1. Debug information keeping the local addressable.
2. `set_imm(self: *@This())` causing the instruction struct to escape.
3. The narrow `u12` accumulator being difficult for LLVM to promote.

The expectation was that identifying the cause would allow the stack traffic
to be removed without changing the decoder's semantics or introducing a
larger code-generation regression.

## What's held fixed

* Target: x86-64.
* Compiler: Zig/LLVM via Godbolt.
* Build mode: `-O ReleaseFast`.
* Function: `decompress_j` (`c.j → jal x0, offset`).
* All `imm_XX_YY` field extraction logic.
* Final instruction construction.
* No wall-clock benchmark or workload changes between variants.

Only the accumulator representation and construction were changed.

## What's varied

| Variant  | Description                                                      |
| -------- | ---------------------------------------------------------------- |
| Baseline | `var imm: u12` with repeated `imm \|= ...`                       |
| A        | Same mutable accumulation; `set_imm` changed to a value receiver |
| B        | `var imm: u32` accumulator with manual sign extension            |
| C        | `const imm: u12 = a \| b \| ... \| h` as one expression          |

## Correctness check

All variants passed a source-level correctness check by inspection. The field
positions and shift/mask constants were identical, and all produced the same
JAL opcode tag (`0x6F`).

No randomized or exhaustive reference-decoder comparison was performed.

| Variant  | Correctness result                                    |
| -------- | ----------------------------------------------------- |
| Baseline | Pass — reference implementation                       |
| A        | Pass — bit-identical to Baseline                      |
| B        | Pass — same field positions, independently re-derived |
| C        | Pass — same extraction constants as Baseline          |

## Method

Each variant was compiled with Zig/LLVM for x86-64 at `-O ReleaseFast` using
Godbolt.

LLVM IR was inspected for the `Case12` block corresponding to `decompress_j`,
specifically for `alloca`, `store`, and `load` operations around `imm`.
Generated assembly was then checked for the surviving stack store.

`llvm-mca` was used on the isolated store to estimate its uOp, latency,
throughput, and port usage.

No wall-clock benchmark against a real instruction stream was performed.

## Result

| Variant  | Metric       | Value   | Delta vs baseline | Notes                                                     |
| -------- | ------------ | ------- | ----------------- | --------------------------------------------------------- |
| Baseline | Alloca/store | Present | —                 | Narrow mutable accumulator leaves a stack store           |
| A        | Alloca/store | Present | None              | IR/assembly was byte-identical to Baseline                |
| B        | Alloca/store | Removed | Better            | Removes stack traffic but triggers AVX2 SLP vectorization |
| C        | Alloca/store | Removed | Better            | Removes stack traffic while retaining scalar codegen      |

The baseline produced a wider stack slot for the `u12` accumulator. Multiple
partial-width stores/loads prevented LLVM from fully promoting the mutable
local to SSA, leaving one physical store in the generated assembly.

Changing only the receiver convention did not affect this.

Widening the accumulator to `u32` removed the alloca, but caused LLVM to
SLP-vectorize the field extraction into an AVX2 sequence involving
`vpbroadcastd`, `vpsrlvd`, `vpsllvd`, `vpblendd`, `vpshufd`, and `vzeroupper`.
This is undesirable for a scalar decoder called once per instruction.

Variant C removed the alloca without changing the accumulator width or field
extraction logic. The resulting assembly remained scalar.

The surviving baseline store was modeled by `llvm-mca` as:

| Metric                |           Value |
| --------------------- | --------------: |
| uOps                  |               1 |
| Latency               |         1 cycle |
| Reciprocal throughput |            1.00 |
| Port                  | Store-data port |
| Dependent reload      |            None |

The store is therefore cheap in isolation and does not extend the critical
path, but Variant C removes it at no apparent code-generation cost.

## Verdict

**Variant C becomes the implementation pattern.**

Construct narrow bitfields as a single `const` expression:

```zig
const imm: uN = a | b | c | ...;
```

rather than mutating a narrow accumulator across multiple statements:

```zig
var imm: uN = a;
imm |= b;
imm |= c;
```

Variant C is preferable because it:

* removes the unnecessary stack traffic;
* preserves the original accumulator width;
* preserves the existing extraction logic;
* avoids the SLP-vectorization regression seen with Variant B;
* requires the smallest source change.

The broader takeaway is that performance-sensitive decoder code should prefer
single-expression bitfield construction when several independently computed
pieces are combined, particularly for non-byte-sized integer widths such as
`u12`.

## Follow-up questions raised

* **Q4:** Does the unconditional `push rbp`/`pop rbp` survive under normal
  production linkage, inlining, and LTO?
