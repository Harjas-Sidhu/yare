const std = @import("std");
const assert = std.debug.assert;

comptime {
    assert(@sizeOf(u64) == 8);
    assert(@sizeOf(u32) == 4);
    assert(@sizeOf(u16) == 2);
    assert(@sizeOf(u8) == 1);
}

pc: u64,
regs: [32]u64,
dram: []u8,

const Self = @This();

/// Clears the provided DRAM buffer.
pub fn init(hart: *Self, pc_initial: u64, dram: []u8) void {
    // must be large enough for the widest dram access (u64).
    assert(dram.len >= @sizeOf(u64));

    // Zero DRAM so the initial state is deterministic.
    @memset(dram, 0);

    hart.* = .{
        .pc = pc_initial,
        .regs = [_]u64{0} ** 32,
        .dram = dram,
    };
}

pub inline fn load_reg(hart: *const Self, index: u5) u64 {
    return hart.regs[index];
}

pub inline fn store_reg(hart: *Self, index: u5, value: u64) void {
    // x0 is architecturally hardwired to zero - by RISC-V SPEC.
    if (index != 0) {
        hart.regs[index] = value;
    }
}

pub inline fn load_dram(
    hart: *const Self,
    comptime T: type,
    offset: u64,
) T {
    comptime validate_type(T);
    const access_size: u64 = @sizeOf(T);

    assert(hart.dram.len >= access_size);
    assert(offset <= hart.dram.len - access_size);

    return std.mem.readInt(T, hart.dram[offset..][0..access_size], .little);
}

pub inline fn store_dram(
    hart: *Self,
    comptime T: type,
    offset: u64,
    value: T,
) void {
    comptime validate_type(T);
    const access_size: u64 = @sizeOf(T);

    assert(hart.dram.len >= access_size);
    assert(offset <= hart.dram.len - access_size);

    std.mem.writeInt(T, hart.dram[offset..][0..access_size], value, .little);
}

inline fn validate_type(comptime T: type) void {
    switch (T) {
        u8, u16, u32, u64 => {},
        else => @compileError("Dram fetch/store requires u8, u16, u32 or u64"),
    }
}

const expectEqual = std.testing.expectEqual;
const PC_INITIAL = 0x8000_0000;

test "Hart.init: zeroes registers and dram, sets pc" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    for (hart.regs) |reg| try expectEqual(0, reg);
    for (hart.dram) |byte| try expectEqual(0, byte);

    try expectEqual(PC_INITIAL, hart.pc);
}

test "Hart: store_reg/load_reg round-trip, x0 hardwired to zero" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    for (0..hart.regs.len) |index| {
        const idx: u5 = @truncate(index);
        const value: u64 = (@as(u64, idx) + 2) * 16;

        try expectEqual(0, hart.load_reg(idx));

        hart.store_reg(idx, value);
        if (index == 0) {
            try expectEqual(0, hart.load_reg(idx));
        } else {
            try expectEqual(value, hart.load_reg(idx));
        }
    }

    for (hart.dram) |byte| try expectEqual(0, byte);
    try expectEqual(PC_INITIAL, hart.pc);
}

test "Hart: x0 remains zero under randomized repeated writes" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const random = prng.random();

    for (0..10000) |_| {
        const value: u64 = random.int(u64);

        hart.store_reg(0, value);
        try expectEqual(0, hart.load_reg(0));
    }
}

test "Hart: store_reg/load_reg boundary values (0, max, mid)" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const MAX: u64 = std.math.maxInt(u64);
    const MID: u64 = MAX >> 1;

    for (1..hart.regs.len) |index| {
        const idx: u5 = @truncate(index);
        try expectEqual(0, hart.load_reg(idx));

        hart.store_reg(idx, MAX);
        try expectEqual(MAX, hart.load_reg(idx));

        hart.store_reg(idx, MID);
        try expectEqual(MID, hart.load_reg(idx));

        hart.store_reg(idx, 0);
        try expectEqual(0, hart.load_reg(idx));
    }
}

test "Hart: store_reg to an index doesn't clobber other indices" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    for (1..hart.regs.len) |index| {
        const idx: u5 = @truncate(index);

        const value: u64 = @as(u64, idx) + 100;
        hart.store_reg(idx, value);
    }

    for (1..hart.regs.len) |index| {
        const idx: u5 = @truncate(index);

        const value: u64 = @as(u64, idx) + 100;
        try expectEqual(value, hart.load_reg(idx));
    }
}

test "Hart.init: zeroes dram for all sizes before any access" {
    var dram: [16]u8 = .{0xFF} ** 16;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const types: [4]type = .{ u8, u16, u32, u64 };

    inline for (types) |T| {
        const zero: T = 0;
        try expectEqual(zero, hart.load_dram(T, 0));
    }

    const offset: u64 = 0 + 8;

    inline for (types) |T| {
        const zero: T = 0;
        try expectEqual(zero, hart.load_dram(T, offset));
    }
}

test "Hart: store_dram/load_dram round-trip for each type" {
    var dram: [64]u8 = .{0xFF} ** 64;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const value: u64 = 0xCAFEBABE_DEADBEEF;
    const types: [4]type = .{ u8, u16, u32, u64 };

    inline for (types) |T| {
        const val: T = @truncate(value);

        hart.store_dram(T, 0, val);
        try expectEqual(val, hart.load_dram(T, 0));
    }
}

test "Hart: load_dram reads correct value through each width after a single u64 store" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const max: u64 = std.math.maxInt(u64);
    hart.store_dram(u64, 0, max);

    const types: [4]type = .{ u8, u16, u32, u64 };

    // Each value should be max, as whole dram is filled with 0xFF
    inline for (types) |T| {
        const value: T = std.math.maxInt(T);
        try expectEqual(value, hart.load_dram(T, 0));
    }
}

test "Hart: store_dram/load_dram at exact upper bound offset for each type" {
    var dram: [16]u8 = .{0xFF} ** 16;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const types: [4]type = .{ u8, u16, u32, u64 };
    const value: u64 = 0x11223344_55667788;

    inline for (types) |T| {
        const offset: u64 = dram.len - @sizeOf(T);
        const val: T = @truncate(value);

        hart.store_dram(T, offset, val);
        try expectEqual(val, hart.load_dram(T, offset));
    }
}

test "Hart: store_dram/load_dram is little-endian" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const value: u64 = 0xCAFEBABE_DEADBEEF;
    hart.store_dram(u64, 0, value);

    try expectEqual(value, hart.load_dram(u64, 0));

    try expectEqual(@as(u32, 0xDEAD_BEEF), hart.load_dram(u32, 0));
    try expectEqual(@as(u32, 0xCAFE_BABE), hart.load_dram(u32, 4));

    try expectEqual(@as(u16, 0xBE_EF), hart.load_dram(u16, 0));
    try expectEqual(@as(u16, 0xDE_AD), hart.load_dram(u16, 2));
    try expectEqual(@as(u16, 0xBA_BE), hart.load_dram(u16, 4));
    try expectEqual(@as(u16, 0xCA_FE), hart.load_dram(u16, 6));

    try expectEqual(@as(u8, 0xEF), hart.load_dram(u8, 0));
    try expectEqual(@as(u8, 0xBE), hart.load_dram(u8, 1));
    try expectEqual(@as(u8, 0xAD), hart.load_dram(u8, 2));
    try expectEqual(@as(u8, 0xDE), hart.load_dram(u8, 3));
    try expectEqual(@as(u8, 0xBE), hart.load_dram(u8, 4));
    try expectEqual(@as(u8, 0xBA), hart.load_dram(u8, 5));
    try expectEqual(@as(u8, 0xFE), hart.load_dram(u8, 6));
    try expectEqual(@as(u8, 0xCA), hart.load_dram(u8, 7));
}

test "Hart: store_dram does not affect bytes outside the written range" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    // resulting byte layout (little-endian):
    // [0]=00 [1]=00 [2]=CE [3]=FA [4]=AD [5]=DE [6]=FE [7]=CA
    hart.store_dram(u16, 2, 0xFACE);
    hart.store_dram(u8, 4, 0xAD);
    hart.store_dram(u8, 5, 0xDE);
    hart.store_dram(u16, 6, 0xCAFE);

    const zero: u8 = 0;

    try expectEqual(zero, hart.load_dram(u8, 0));
    try expectEqual(zero, hart.load_dram(u8, 1));

    try expectEqual(@as(u8, 0xAD), hart.load_dram(u8, 4));
    try expectEqual(@as(u8, 0xDE), hart.load_dram(u8, 5));

    try expectEqual(@as(u16, 0xFACE), hart.load_dram(u16, 2));
    try expectEqual(@as(u16, 0xCAFE), hart.load_dram(u16, 6));
    try expectEqual(@as(u16, 0xDEAD), hart.load_dram(u16, 4));

    try expectEqual(@as(u32, 0xDEADFACE), hart.load_dram(u32, 2));
    try expectEqual(@as(u32, 0xCAFEDEAD), hart.load_dram(u32, 4));
    try expectEqual(@as(u32, 0xFACE0000), hart.load_dram(u32, 0));

    try expectEqual(@as(u64, 0xCAFEDEAD_FACE0000), hart.load_dram(u64, 0));
}

test "Hart: overlapping dram stores and loads" {
    var dram: [8]u8 = .{0xFF} ** 8;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    hart.store_dram(u64, 0, 0xCAFEBEEF_DEADFACE);
    hart.store_dram(u16, 3, 0xAD_BE);

    try expectEqual(@as(u32, 0xBEAD_BEAD), hart.load_dram(u32, 2));

    hart.store_dram(u8, 4, 0xEF);
    try expectEqual(@as(u32, 0xCAFE_BEEF), hart.load_dram(u32, 4));

    hart.store_dram(u8, 0, 0xED);
    hart.store_dram(u8, 1, 0xFE);

    try expectEqual(@as(u32, 0xBEAD_FEED), hart.load_dram(u32, 0));
}

test "Hart: unaligned dram loads and stores" {
    var dram: [64]u8 = .{0xFF} ** 64;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const types: [4]type = .{ u8, u16, u32, u64 };

    var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
    const random = prng.random();

    var offset: u64 = 1;
    while (offset < hart.dram.len) : (offset += 2) {
        inline for (types) |T| {
            const offset_end: u64 = hart.dram.len - @sizeOf(T);

            if (offset <= offset_end) {
                const value: T = random.int(T);
                hart.store_dram(T, offset, value);

                try expectEqual(value, hart.load_dram(T, offset));
            }
        }
    }
}

test "Hart: randomized stores and loads for dram" {
    var dram: [128]u8 = .{0xFF} ** 128;

    var hart: Self = undefined;
    hart.init(PC_INITIAL, &dram);

    const types: [4]type = .{ u8, u16, u32, u64 };

    var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
    const random = prng.random();

    for (0..10000) |_| {
        const type_index: u2 = random.int(u2);

        inline for (types, 0..) |T, index| {
            const idx: u2 = @truncate(index);

            if (idx == type_index) {
                const offset_end: u64 = hart.dram.len - @sizeOf(T);
                const offset: u64 = random.intRangeAtMost(u64, 0, offset_end);

                const value: T = random.int(T);
                hart.store_dram(T, offset, value);

                try expectEqual(value, hart.load_dram(T, offset));
            }
        }
    }
}
