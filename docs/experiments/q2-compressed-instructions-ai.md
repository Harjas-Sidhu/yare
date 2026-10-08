# Q2: [DECISION] Should we use similar API to instruction for compressed instructions?

**Status:** Closed
**Date opened:** 2026-08-01
**Date closed:** 2026-08-02

## Why this question
Supporting the RISC-V C extension requires decoding 16-bit instructions. 
This [DECISION] determines whether compressed instructions should expose 
a field-extraction API similar to `arch/instruction.zig`, or whether they 
should first be expanded into canonical 32-bit instructions before decoding and execution.

## Options considered

| Option | Description                                                                         |
| ------ | ----------------------------------------------------------------------------------- |
| A      | Decode and execute compressed instructions directly using dedicated field accessors |
| B      | Decompress into canonical 32-bit instructions before decode/execution               |


## Tradeoffs

| Criteria          | Direct decode        | Decompress         |
| ----------------- | -------------------- | ------------------ |
| Existing API      | Consistent           | Canonical API      |
| Decode complexity | Higher               | Lower              |
| Execution logic   | Separate paths       | Shared             |
| Maintenance       | Higher               | Lower              |
| Runtime cost      | No expansion         | One expansion step |
| Extensibility     | More duplicated work | Easier             |



## Decision
Compressed instructions will be decompressed into canonical 32-bit instructions before decode and execution.

This approach establishes a single canonical instruction representation throughout the remainder 
of the emulator, allowing compressed and uncompressed instructions to share the same decoding and 
execution logic. Although decompression introduces a small runtime cost, the reduction in 
implementation complexity and maintenance outweighs the expected overhead.

If profiling later demonstrates that decompression is a measurable bottleneck, this decision may be revisited.

## Follow-up questions raised
Performance should be validated with profiling after implementing the `C` extension.
