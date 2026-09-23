const Hart = @import("../hart.zig");
const Instruction = @import("instruction.zig");

// Execution function pointer, used for tail call dispatch via
// @call(.always_tail, handler, .{ &hart, instruction })
pub const Handler = *const fn (hart: *Hart, instruction: Instruction) void;

// Sentinel for uninitialized/unreachable handler slots.
pub fn exec_unreachable(_: *Hart, _: Instruction) void {
    unreachable;
}

pub fn exec_nop(_: *Hart, _: Instruction) void {}
