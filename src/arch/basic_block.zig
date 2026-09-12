const std = @import("std");
const Instruction = @import("instruction.zig");
const handle = @import("handler.zig");

const assert = std.debug.assert;
const Handler = handle.Handler;
const exec_unreachable = handle.exec_unreachable;
const exec_nop = handle.exec_nop;

/// To be kept as power of 2.
const BLOCK_CAPACITY = 64;
comptime {
    assert(std.math.isPowerOfTwo(BLOCK_CAPACITY));
}

const ILLEGAL_INSTRUCTION: Instruction = .{ .raw = Instruction.ILLEGAL_INSTRUCTION };
const COMPRESSED_INSTRUCTION_BYTES: u8 = 2;

const MaskType = @Int(.unsigned, BLOCK_CAPACITY);
const ShiftType = std.math.IntFittingRange(0, BLOCK_CAPACITY - 1);
const SizeType = std.math.IntFittingRange(0, BLOCK_CAPACITY);

pub const BasicBlock = struct {
    pc_entry: u64,
    pc_exit: u64,

    // One bit per instruction:
    //   0 = 16-bit compressed instruction
    //   1 = 32-bit full-width instruction
    // Starts from LSB, i.e 1st instruction size at LSB.
    instruction_length_mask: MaskType,

    // For 0 <= i < instruction_count:
    // instructions[i] and handlers[i] are live entries.
    instruction_count: SizeType,

    // A sentinel instruction, added at index instruction_count.
    // Anything after sentinel is unused, set to unreachable.
    instructions: [BLOCK_CAPACITY + 1]Instruction,

    // Value handlers[instruction_count] always holds the sentinel handler.
    // This removes the need for central dispatch and bookkeeping.
    handlers: [BLOCK_CAPACITY + 1]Handler,

    const Self = @This();

    fn assertInvariants(basic_block: *const Self) void {
        assert(basic_block.instruction_count <= BLOCK_CAPACITY);
        assert(basic_block.handlers[basic_block.instruction_count] != exec_unreachable);
    }

    pub fn init(basic_block: *Self, pc_entry: u64, sentinel_handler: Handler) void {
        assert(sentinel_handler != exec_unreachable);

        basic_block.* = .{
            .pc_entry = pc_entry,
            .pc_exit = pc_entry,
            .instruction_length_mask = 0,
            .instruction_count = 0,
            .instructions = .{ILLEGAL_INSTRUCTION} ** (BLOCK_CAPACITY + 1),
            .handlers = .{exec_unreachable} ** (BLOCK_CAPACITY + 1),
        };

        basic_block.handlers[0] = sentinel_handler;
        basic_block.assertInvariants();
    }

    pub fn pc_offset(basic_block: *const Self, instruction_index: ShiftType) u64 {
        basic_block.assertInvariants();
        assert(instruction_index < basic_block.instruction_count);

        // Count full-width instructions among entries [0, count).
        const preceding_mask = (@as(MaskType, 1) << instruction_index) - 1;
        const full_width_count = @popCount(
            basic_block.instruction_length_mask & preceding_mask,
        );

        // Each instruction contributes at least 2 bytes.
        // Each full-width instruction contributes one additional 2-byte unit.
        const offset = (@as(u64, instruction_index) + full_width_count) << 1;
        return basic_block.pc_entry + offset;
    }

    /// instruction_count must be less than BLOCK_CAPACITY
    pub fn append(
        basic_block: *Self,
        instruction: Instruction,
        handler: Handler,
        is_full_width: bool,
    ) void {
        basic_block.assertInvariants();
        assert(handler != exec_unreachable);

        const index = basic_block.instruction_count;
        const shift: ShiftType = @intCast(index);

        const sentinel_handler = basic_block.handlers[index];

        basic_block.instructions[index] = instruction;
        basic_block.handlers[index] = handler;

        basic_block.handlers[index + 1] = sentinel_handler;

        const bit: u1 = @intFromBool(is_full_width);
        const mask: MaskType = @as(MaskType, bit) << shift;

        basic_block.pc_exit += (COMPRESSED_INSTRUCTION_BYTES << bit);
        basic_block.instruction_length_mask |= mask;

        basic_block.instruction_count += 1;
    }
};

const expectEqual = std.testing.expectEqual;

const PC_ENTRY: u32 = 0x8000_0000;

test "BasicBlock: basic init" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    try expectEqual(PC_ENTRY, basic_block.pc_entry);
    try expectEqual(PC_ENTRY, basic_block.pc_exit);

    try expectEqual(0, basic_block.instruction_count);

    for (basic_block.instructions) |instruction| {
        try expectEqual(ILLEGAL_INSTRUCTION, instruction);
    }

    for (basic_block.handlers, 0..) |handler, index| {
        if (index == 0) continue;
        try expectEqual(exec_unreachable, handler);
    }

    // sentinel
    try expectEqual(exec_nop, basic_block.handlers[0]);
}

test "BasicBlock: basic append" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    for (0..BLOCK_CAPACITY) |index| {
        const instruction: Instruction = .{ .raw = @intCast(index + 1) };
        basic_block.append(instruction, exec_nop, true);
    }

    try expectEqual(BLOCK_CAPACITY, basic_block.instruction_count);
    try expectEqual(std.math.maxInt(MaskType), basic_block.instruction_length_mask);

    const pc_exit = PC_ENTRY + (BLOCK_CAPACITY << 2);
    try expectEqual(pc_exit, basic_block.pc_exit);

    for (0..BLOCK_CAPACITY) |index| {
        const instruction: Instruction = .{ .raw = @intCast(index + 1) };
        try expectEqual(instruction, basic_block.instructions[index]);
        try expectEqual(exec_nop, basic_block.handlers[index]);
    }

    try expectEqual(exec_nop, basic_block.handlers[BLOCK_CAPACITY]);
}

test "BasicBlock: alternate compressed instructions" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    var instruction_length_mask: MaskType = 0;

    for (0..BLOCK_CAPACITY) |index| {
        const is_full_width = (index % 2 == 0);
        const instruction: Instruction = .{ .raw = @intCast(index + 1) };
        basic_block.append(instruction, exec_nop, is_full_width);

        instruction_length_mask |=
            @as(MaskType, @intFromBool(is_full_width)) << @intCast(index);
    }

    try expectEqual(BLOCK_CAPACITY, basic_block.instruction_count);
    try expectEqual(instruction_length_mask, basic_block.instruction_length_mask);

    const pc_exit = PC_ENTRY + BLOCK_CAPACITY + (BLOCK_CAPACITY << 1);
    try expectEqual(pc_exit, basic_block.pc_exit);

    for (0..BLOCK_CAPACITY) |index| {
        const instruction: Instruction = .{ .raw = @intCast(index + 1) };
        try expectEqual(instruction, basic_block.instructions[index]);
        try expectEqual(exec_nop, basic_block.handlers[index]);

        const is_full_width = @intFromBool(index % 2 == 0);
        const is_full_width_from_mask: u1 =
            @truncate(instruction_length_mask >> @intCast(index));

        try expectEqual(is_full_width, is_full_width_from_mask);
    }

    try expectEqual(exec_nop, basic_block.handlers[BLOCK_CAPACITY]);
}

test "BasicBlock: pc_offset" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    var instruction_length_mask: MaskType = 0;

    for (0..BLOCK_CAPACITY) |index| {
        const is_full_width = (index % 2 == 0);
        const instruction: Instruction = .{ .raw = @intCast(index + 1) };
        basic_block.append(instruction, exec_nop, is_full_width);

        instruction_length_mask |=
            @as(MaskType, @intFromBool(is_full_width)) << @intCast(index);
    }

    try expectEqual(BLOCK_CAPACITY, basic_block.instruction_count);
    try expectEqual(instruction_length_mask, basic_block.instruction_length_mask);

    const pc_exit = PC_ENTRY + BLOCK_CAPACITY + (BLOCK_CAPACITY << 1);
    try expectEqual(pc_exit, basic_block.pc_exit);

    var pc_value = basic_block.pc_entry;

    for (0..BLOCK_CAPACITY) |index| {
        const instruction: Instruction = .{ .raw = @intCast(index + 1) };
        try expectEqual(instruction, basic_block.instructions[index]);
        try expectEqual(exec_nop, basic_block.handlers[index]);

        const is_full_width = @intFromBool(index % 2 == 0);
        const is_full_width_from_mask: u1 =
            @truncate(instruction_length_mask >> @intCast(index));

        try expectEqual(is_full_width, is_full_width_from_mask);

        if (index == 0) continue;

        const is_prev_full_width = ~is_full_width;
        pc_value += if (is_prev_full_width == 0) 2 else 4;

        try expectEqual(pc_value, basic_block.pc_offset(@intCast(index)));
    }

    const instruction_index: ShiftType = @intCast(basic_block.instruction_count - 1);

    try expectEqual(pc_exit, basic_block.pc_offset(instruction_index) + 2);
    try expectEqual(exec_nop, basic_block.handlers[BLOCK_CAPACITY]);
}

test "BasicBlock: single instruction" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    basic_block.append(.{ .raw = 0x1234 }, exec_nop, false);

    try expectEqual(1, basic_block.instruction_count);
    try expectEqual(PC_ENTRY, basic_block.pc_offset(0));
    try expectEqual(PC_ENTRY + 2, basic_block.pc_exit);
    try expectEqual(exec_nop, basic_block.handlers[0]);
    try expectEqual(exec_nop, basic_block.handlers[1]);
}

test "BasicBlock: single full-width instruction" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    basic_block.append(.{ .raw = 0x1234 }, exec_nop, true);

    try expectEqual(1, basic_block.instruction_count);
    try expectEqual(PC_ENTRY, basic_block.pc_offset(0));
    try expectEqual(PC_ENTRY + 4, basic_block.pc_exit);
}

test "BasicBlock: pc_offset with one full-width instruction" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    for (0..BLOCK_CAPACITY) |full_width_index| {
        basic_block.init(PC_ENTRY, exec_nop);

        for (0..BLOCK_CAPACITY) |index| {
            const is_full_width = index == full_width_index;
            const instruction: Instruction = .{
                .raw = @intCast(index + 1),
            };

            basic_block.append(instruction, exec_nop, is_full_width);
        }

        for (0..BLOCK_CAPACITY) |index| {
            const size_correction: u8 = if (index > full_width_index) 2 else 0;
            const expected_offset = @as(u64, index) * 2 + size_correction + PC_ENTRY;
            try expectEqual(expected_offset, basic_block.pc_offset(@intCast(index)));
        }

        const expected_pc_exit = PC_ENTRY + (BLOCK_CAPACITY * 2) + 2;
        try expectEqual(expected_pc_exit, basic_block.pc_exit);
    }
}

test "BasicBlock: instruction length mask highest bit" {
    var basic_block: BasicBlock = undefined;
    basic_block.init(PC_ENTRY, exec_nop);

    for (0..BLOCK_CAPACITY - 1) |index| {
        basic_block.append(.{ .raw = @intCast(index + 1) }, exec_nop, false);
    }

    basic_block.append(.{ .raw = 0xCAFE }, exec_nop, true);

    const mask = @as(MaskType, 1) << (BLOCK_CAPACITY - 1);
    const pc_exit = basic_block.pc_entry + (BLOCK_CAPACITY * 2) + 2;
    const pc_offset = basic_block.pc_entry + ((BLOCK_CAPACITY - 1) * 2);

    try expectEqual(mask, basic_block.instruction_length_mask);
    try expectEqual(pc_exit, basic_block.pc_exit);
    try expectEqual(pc_offset, basic_block.pc_offset(BLOCK_CAPACITY - 1));
}

test "BasicBlock: partial blocks" {
    var prng = std.Random.DefaultPrng.init(0xF1F0F1FA);
    const random = prng.random();

    for (0..BLOCK_CAPACITY + 1) |size| {
        const block_size: SizeType = @intCast(size);

        var basic_block: BasicBlock = undefined;
        basic_block.init(PC_ENTRY, exec_nop);

        try expectEqual(PC_ENTRY, basic_block.pc_entry);
        try expectEqual(PC_ENTRY, basic_block.pc_exit);
        try expectEqual(0, basic_block.instruction_count);
        try expectEqual(0, basic_block.instruction_length_mask);
        try expectEqual(exec_nop, basic_block.handlers[0]);

        for (0..BLOCK_CAPACITY) |index| {
            try expectEqual(ILLEGAL_INSTRUCTION, basic_block.instructions[index]);
        }

        for (1..BLOCK_CAPACITY) |index| {
            try expectEqual(exec_unreachable, basic_block.handlers[index]);
        }

        var instructions: [BLOCK_CAPACITY + 1]Instruction = undefined;
        var pc_values: [BLOCK_CAPACITY]u64 = undefined;
        var pc_end_value = basic_block.pc_entry;
        var instruction_mask: MaskType = 0;

        for (0..block_size) |index| {
            const is_full_width = random.boolean();
            const instruction: Instruction = .{ .raw = random.int(u32) };

            instructions[index] = instruction;
            pc_end_value += if (is_full_width) 4 else 2;
            pc_values[index] = pc_end_value;

            const mask = @as(MaskType, @intFromBool(is_full_width)) << @intCast(index);
            instruction_mask |= mask;

            basic_block.append(instruction, exec_nop, is_full_width);
        }

        try expectEqual(PC_ENTRY, basic_block.pc_entry);
        try expectEqual(pc_end_value, basic_block.pc_exit);
        try expectEqual(block_size, basic_block.instruction_count);
        try expectEqual(instruction_mask, basic_block.instruction_length_mask);

        for (0..block_size) |index| {
            try expectEqual(instructions[index], basic_block.instructions[index]);
        }

        for (block_size..BLOCK_CAPACITY + 1) |index| {
            try expectEqual(ILLEGAL_INSTRUCTION, basic_block.instructions[index]);
        }

        for (0..block_size) |index| {
            try expectEqual(exec_nop, basic_block.handlers[index]);
        }

        // sentinel
        try expectEqual(exec_nop, basic_block.handlers[block_size]);

        const after_sentinel_index = @as(u64, block_size) + 1;

        for (after_sentinel_index..BLOCK_CAPACITY + 1) |index| {
            try expectEqual(exec_unreachable, basic_block.handlers[index]);
        }

        if (block_size < 1) continue;

        for (0..block_size - 1) |index| {
            try expectEqual(pc_values[index], basic_block.pc_offset(@intCast(index + 1)));
        }
    }
}

test "BasicBlock: randomized test" {
    var prng = std.Random.DefaultPrng.init(0xBADC0FFE);
    const random = prng.random();

    for (0..100000) |_| {
        var basic_block: BasicBlock = undefined;
        basic_block.init(random.int(u64), exec_nop);

        const block_size = random.intRangeAtMost(usize, 0, BLOCK_CAPACITY);

        var expected_pc = basic_block.pc_entry;
        var expected_mask: MaskType = 0;

        var expected_pc_after: [BLOCK_CAPACITY]u64 = undefined;
        var expected_instructions: [BLOCK_CAPACITY]Instruction = undefined;

        for (0..block_size) |index| {
            const is_full_width = random.boolean();
            const raw = random.int(u32);

            const instruction: Instruction = .{ .raw = raw };
            expected_instructions[index] = instruction;

            if (is_full_width) {
                expected_mask |= @as(MaskType, 1) << @intCast(index);
                expected_pc += 4;
            } else {
                expected_pc += 2;
            }

            expected_pc_after[index] = expected_pc;
            basic_block.append(instruction, exec_nop, is_full_width);
        }

        try expectEqual(block_size, basic_block.instruction_count);
        try expectEqual(expected_mask, basic_block.instruction_length_mask);
        try expectEqual(expected_pc, basic_block.pc_exit);

        for (0..block_size) |index| {
            try expectEqual(expected_instructions[index], basic_block.instructions[index]);
            try expectEqual(exec_nop, basic_block.handlers[index]);
        }

        if (block_size != 0) {
            for (0..block_size) |index| {
                const count: ShiftType = @intCast(index);

                const expected_pc_at_instruction =
                    if (index == 0)
                        basic_block.pc_entry
                    else
                        expected_pc_after[index - 1];

                try expectEqual(expected_pc_at_instruction, basic_block.pc_offset(count));

                const is_full_width = ((expected_mask >> @intCast(index)) & 1) != 0;
                const instruction_size: u64 = if (is_full_width) 4 else 2;
                const pc_after = expected_pc_at_instruction + instruction_size;

                try expectEqual(pc_after, expected_pc_after[index]);
            }

            const last = block_size - 1;
            const last_is_full_width = ((expected_mask >> @intCast(last)) & 1) != 0;
            const last_size: u64 = if (last_is_full_width) 4 else 2;
            const pc_exit = basic_block.pc_offset(@intCast(last)) + last_size;

            try expectEqual(basic_block.pc_exit, pc_exit);
        } else {
            try expectEqual(basic_block.pc_entry, basic_block.pc_exit);
        }

        try expectEqual(exec_nop, basic_block.handlers[block_size]);
        try expectEqual(ILLEGAL_INSTRUCTION, basic_block.instructions[block_size]);
    }
}
