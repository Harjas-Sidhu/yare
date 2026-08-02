const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const sign_extend = @import("sign_extend.zig").sign_extend;

raw: u32,

const Self = @This();

pub inline fn opcode(self: Self) u7 {
    return @truncate(self.raw);
}

pub inline fn rd(self: Self) u5 {
    return @truncate(self.raw >> 7);
}

pub inline fn funct3(self: Self) u3 {
    return @truncate(self.raw >> 12);
}

pub inline fn rs1(self: Self) u5 {
    return @truncate(self.raw >> 15);
}

pub inline fn rs2(self: Self) u5 {
    return @truncate(self.raw >> 20);
}

pub inline fn funct7(self: Self) u7 {
    return @truncate(self.raw >> 25);
}

// RV64I shift-immediate instructions use a 6-bit shift amount
pub inline fn shamt(self: Self) u6 {
    return @truncate(self.raw >> 20);
}

pub inline fn funct6(self: Self) u6 {
    return @truncate(self.raw >> 26);
}

// imm[11:0]
pub inline fn imm_I(self: Self) u12 {
    return @truncate(self.raw >> 20);
}

pub inline fn simm_I(self: Self) i64 {
    return sign_extend(self.imm_I());
}

// same space as I-immediate
pub inline fn csr(self: Self) u12 {
    return self.imm_I();
}

// imm[11:5] | imm[4:0]
pub inline fn imm_S(self: Self) u12 {
    const imm_04_00: u5 = @truncate(self.raw >> 7);
    const imm_11_05: u7 = @truncate(self.raw >> 25);

    var imm: u12 = 0;

    imm |= @as(u12, imm_11_05) << 5;
    imm |= @as(u12, imm_04_00);

    return imm;
}

pub inline fn simm_S(self: Self) i64 {
    return sign_extend(self.imm_S());
}

// imm[12] | imm[11] | imm[10:5] | imm[4:1] | 0
pub inline fn imm_B(self: Self) u13 {
    const imm_04_01: u4 = @truncate(self.raw >> 8);
    const imm_11_11: u1 = @truncate(self.raw >> 7);
    const imm_10_05: u6 = @truncate(self.raw >> 25);
    const imm_12_12: u1 = @truncate(self.raw >> 31);

    var imm: u13 = 0;

    imm |= @as(u13, imm_12_12) << 12;
    imm |= @as(u13, imm_11_11) << 11;
    imm |= @as(u13, imm_10_05) << 5;
    imm |= @as(u13, imm_04_01) << 1;

    return imm;
}

pub inline fn simm_B(self: Self) i64 {
    return sign_extend(self.imm_B());
}

// imm[31:12] | 000000000000
pub inline fn imm_U(self: Self) u32 {
    const imm_31_12: u20 = @truncate(self.raw >> 12);
    const imm: u32 = @as(u32, imm_31_12) << 12;

    return imm;
}

pub inline fn simm_U(self: Self) i64 {
    return sign_extend(self.imm_U());
}

// imm[20] | imm[19:12] | imm[11] | imm[10:1] | 0
pub inline fn imm_J(self: Self) u21 {
    const imm_19_12: u8 = @truncate(self.raw >> 12);
    const imm_11_11: u1 = @truncate(self.raw >> 20);
    const imm_10_01: u10 = @truncate(self.raw >> 21);
    const imm_20_20: u1 = @truncate(self.raw >> 31);

    var imm: u21 = 0;

    imm |= @as(u21, imm_20_20) << 20;
    imm |= @as(u21, imm_19_12) << 12;
    imm |= @as(u21, imm_11_11) << 11;
    imm |= @as(u21, imm_10_01) << 1;

    return imm;
}

pub inline fn simm_J(self: Self) i64 {
    return sign_extend(self.imm_J());
}

// funct7 | rs2 | rs1 | funct3 | rd | opcode
pub const RFields = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    funct7: u7,
};

// imm[11:0] | rs1 | funct3 | rd | opcode
pub const IFields = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm_11_00: u12,

    pub fn get_imm(self: *const @This()) u12 {
        return self.imm_11_00;
    }

    pub fn set_imm(self: *@This(), imm: u12) void {
        self.imm_11_00 = imm;
    }
};

// imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
pub const SFields = packed struct(u32) {
    opcode: u7,
    imm_04_00: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm_11_05: u7,

    pub fn get_imm(self: *const @This()) u12 {
        return @as(u12, self.imm_11_05) << 5 |
            @as(u12, self.imm_04_00);
    }

    pub fn set_imm(self: *@This(), imm: u12) void {
        self.imm_04_00 = @truncate(imm);
        self.imm_11_05 = @truncate(imm >> 5);
    }
};

// imm[12:12] | imm[10:5] | rs2 | rs1 | funct3 | imm[4:1] | imm[11:11] | opcode
pub const BFields = packed struct(u32) {
    opcode: u7,
    imm_11_11: u1,
    imm_04_01: u4,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm_10_05: u6,
    imm_12_12: u1,

    pub fn get_imm(self: *const @This()) u13 {
        return @as(u13, self.imm_12_12) << 12 |
            @as(u13, self.imm_11_11) << 11 |
            @as(u13, self.imm_10_05) << 5 |
            @as(u13, self.imm_04_01) << 1;
    }

    pub fn set_imm(self: *@This(), imm: u13) void {
        self.imm_04_01 = @truncate(imm >> 1);
        self.imm_10_05 = @truncate(imm >> 5);
        self.imm_11_11 = @truncate(imm >> 11);
        self.imm_12_12 = @truncate(imm >> 12);
    }
};

// imm[31:12] |  rd | opcode
pub const UFields = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm_31_12: u20,

    pub fn get_imm(self: *const @This()) u32 {
        return @as(u32, self.imm_31_12) << 12;
    }

    pub fn set_imm(self: *@This(), imm: u32) void {
        self.imm_31_12 = @truncate(imm >> 12);
    }
};

// imm[20:20] | imm[10:1] | imm[11:11] | imm[19:12] |  rd | opcode
pub const JFields = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm_19_12: u8,
    imm_11_11: u1,
    imm_10_01: u10,
    imm_20_20: u1,

    pub fn get_imm(self: *const @This()) u21 {
        return
            @as(u21, self.imm_20_20) << 20 |
            @as(u21, self.imm_19_12) << 12 |
            @as(u21, self.imm_11_11) << 11 |
            @as(u21, self.imm_10_01) << 1;
    }

    pub fn set_imm(self: *@This(), imm: u21) void {
        self.imm_10_01 = @truncate(imm >> 1);
        self.imm_11_11 = @truncate(imm >> 11);
        self.imm_19_12 = @truncate(imm >> 12);
        self.imm_20_20 = @truncate(imm >> 20);
    }
};

// funct6 | shamt | rs1 | funct3 | rd | opcode
pub const ShiftIFields = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    shamt: u6,
    funct6: u6,
};

// Log2Int(T) is the smallest legal type, allows safet shifts.
fn highest_bit_index(comptime T: type) std.math.Log2Int(T) {
    return @typeInfo(T).int.bits - 1;
}

fn generate_common(comptime T: type) [6]T {
    const MAX: T = std.math.maxInt(T);
    const MSB: T = @as(T, 1) << highest_bit_index(T);
    return .{ 0, 1, MAX, MAX >> 1, MAX - 1, MSB };
}

fn get_raw(fields: anytype) u32 {
    return @bitCast(fields);
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for R-type" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u3 = generate_common(u3);

    for (_u7) |_funct7| {
        for (_u5) |_rs2| {
            for (_u5) |_rs1| {
                for (_u3) |_funct3| {
                    for (_u5) |_rd| {
                        for (_u7) |_opcode| {
                            const fields: RFields = .{
                                .opcode = _opcode,
                                .rd = _rd,
                                .funct3 = _funct3,
                                .rs1 = _rs1,
                                .rs2 = _rs2,
                                .funct7 = _funct7,
                            };

                            const raw = get_raw(fields);
                            const decoded: Self = .{ .raw = raw };

                            try expectEqual(fields.funct7, decoded.funct7());
                            try expectEqual(fields.rs2, decoded.rs2());
                            try expectEqual(fields.rs1, decoded.rs1());
                            try expectEqual(fields.funct3, decoded.funct3());
                            try expectEqual(fields.rd, decoded.rd());
                            try expectEqual(fields.opcode, decoded.opcode());
                        }
                    }
                }
            }
        }
    }
}

test "Instruction: real R-type examples" {
    const instructions = [_]RFields{
        @bitCast(@as(u32, 0x003100B3)), // add  x1,  x2,  x3
        @bitCast(@as(u32, 0x40628233)), // sub  x4,  x5,  x6
        @bitCast(@as(u32, 0x009413B3)), // sll  x7,  x8,  x9
        @bitCast(@as(u32, 0x00C5A533)), // slt  x10, x11, x12
        @bitCast(@as(u32, 0x00F736B3)), // sltu x13, x14, x15
        @bitCast(@as(u32, 0x0128C833)), // xor  x16, x17, x18
        @bitCast(@as(u32, 0x015A59B3)), // srl  x19, x20, x21
        @bitCast(@as(u32, 0x418BDB33)), // sra  x22, x23, x24
        @bitCast(@as(u32, 0x01BD6CB3)), // or   x25, x26, x27
        @bitCast(@as(u32, 0x01EEFE33)), // and  x28, x29, x30
        @bitCast(@as(u32, 0x00100FB3)), // add  x31, x0,  x1
        @bitCast(@as(u32, 0x40018133)), // sub  x2,  x3,  x0
        @bitCast(@as(u32, 0x00629233)), // sll  x4,  x5,  x6
        @bitCast(@as(u32, 0x009423B3)), // slt  x7,  x8,  x9
        @bitCast(@as(u32, 0x00C5B533)), // sltu x10, x11, x12
        @bitCast(@as(u32, 0x00F746B3)), // xor  x13, x14, x15
        @bitCast(@as(u32, 0x0128D833)), // srl  x16, x17, x18
        @bitCast(@as(u32, 0x415A59B3)), // sra  x19, x20, x21
        @bitCast(@as(u32, 0x018BEB33)), // or   x22, x23, x24
        @bitCast(@as(u32, 0x01BD7CB3)), // and  x25, x26, x27
    };

    // one manual test for first instruction
    const raw_manual: u32 = get_raw(instructions[0]);
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(51, decoded_manual.opcode());
    try expectEqual(1, decoded_manual.rd());
    try expectEqual(0, decoded_manual.funct3());
    try expectEqual(2, decoded_manual.rs1());
    try expectEqual(3, decoded_manual.rs2());
    try expectEqual(0, decoded_manual.funct7());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(inst.opcode, decoded.opcode());
        try expectEqual(inst.rd, decoded.rd());
        try expectEqual(inst.funct3, decoded.funct3());
        try expectEqual(inst.rs1, decoded.rs1());
        try expectEqual(inst.rs2, decoded.rs2());
        try expectEqual(inst.funct7, decoded.funct7());
    }
}

test "Instruction: randomized R-types fields" {
    var prng = std.Random.DefaultPrng.init(0xDEADFACE);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: RFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(fields.opcode, decoded.opcode());
        try expectEqual(fields.rd, decoded.rd());
        try expectEqual(fields.funct3, decoded.funct3());
        try expectEqual(fields.rs1, decoded.rs1());
        try expectEqual(fields.rs2, decoded.rs2());
        try expectEqual(fields.funct7, decoded.funct7());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for I-type" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u3 = generate_common(u3);
    const _u12 = generate_common(u12);

    for (_u12) |_imm| {
        for (_u5) |_rs1| {
            for (_u3) |_funct3| {
                for (_u5) |_rd| {
                    for (_u7) |_opcode| {
                        var fields: IFields = .{
                            .opcode = _opcode,
                            .rd = _rd,
                            .funct3 = _funct3,
                            .rs1 = _rs1,
                            .imm_11_00 = 0,
                        };

                        fields.set_imm(_imm);

                        const raw = get_raw(fields);
                        const decoded: Self = .{ .raw = raw };

                        try expectEqual(fields.get_imm(), decoded.imm_I());
                        try expectEqual(fields.rs1, decoded.rs1());
                        try expectEqual(fields.funct3, decoded.funct3());
                        try expectEqual(fields.rd, decoded.rd());
                        try expectEqual(fields.opcode, decoded.opcode());

                        const signed_imm: i12 = @bitCast(decoded.imm_I());
                        try expectEqual(@as(i64, signed_imm), decoded.simm_I());
                    }
                }
            }
        }
    }
}

test "Instruction: real I-type examples" {
    const instructions = [_]IFields{
        @bitCast(@as(u32, 0x00010093)), // addi  x1,  x2, 0
        @bitCast(@as(u32, 0x00120193)), // addi  x3,  x4, 1
        @bitCast(@as(u32, 0xFFF30293)), // addi  x5,  x6, -1
        @bitCast(@as(u32, 0x7FF40393)), // addi  x7,  x8, 2047
        @bitCast(@as(u32, 0x80050493)), // addi  x9,  x10, -2048
        @bitCast(@as(u32, 0x00062593)), // slti  x11, x12, 0
        @bitCast(@as(u32, 0x02A72693)), // slti  x13, x14, 42
        @bitCast(@as(u32, 0xFD682793)), // slti  x15, x16, -42
        @bitCast(@as(u32, 0x00093893)), // sltiu x17, x18, 0
        @bitCast(@as(u32, 0x02AA3993)), // sltiu x19, x20, 42
        @bitCast(@as(u32, 0x055B4A93)), // xori  x21, x22, 0x55
        @bitCast(@as(u32, 0xFFFC4B93)), // xori  x23, x24, -1
        @bitCast(@as(u32, 0x123D6C93)), // ori   x25, x26, 0x123
        @bitCast(@as(u32, 0xFFFE6D93)), // ori   x27, x28, -1
        @bitCast(@as(u32, 0x07FF7E93)), // andi  x29, x30, 0x7F
        @bitCast(@as(u32, 0xF800FF93)), // andi  x31, x1,  -128
        @bitCast(@as(u32, 0x00119113)), // slli  x2,  x3, 1
        @bitCast(@as(u32, 0x03F29213)), // slli  x4,  x5, 63
        @bitCast(@as(u32, 0x0083D313)), // srli  x6,  x7, 8
        @bitCast(@as(u32, 0x41F4D413)), // srai  x8,  x9, 31
    };

    // one manual test for first instruction
    const raw_manual: u32 = get_raw(instructions[0]);
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(19, decoded_manual.opcode());
    try expectEqual(1, decoded_manual.rd());
    try expectEqual(0, decoded_manual.funct3());
    try expectEqual(2, decoded_manual.rs1());
    try expectEqual(0, decoded_manual.imm_I());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(inst.opcode, decoded.opcode());
        try expectEqual(inst.rd, decoded.rd());
        try expectEqual(inst.funct3, decoded.funct3());
        try expectEqual(inst.rs1, decoded.rs1());
        try expectEqual(inst.get_imm(), decoded.imm_I());

        const signed_imm: i12 = @bitCast(decoded.imm_I());
        try expectEqual(@as(i64, signed_imm), decoded.simm_I());
    }
}

test "Instruction: randomized I-types fields" {
    var prng = std.Random.DefaultPrng.init(0xDEADFEED);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: IFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(fields.opcode, decoded.opcode());
        try expectEqual(fields.rd, decoded.rd());
        try expectEqual(fields.funct3, decoded.funct3());
        try expectEqual(fields.rs1, decoded.rs1());
        try expectEqual(fields.get_imm(), decoded.imm_I());

        const signed_imm: i12 = @bitCast(decoded.imm_I());
        try expectEqual(@as(i64, signed_imm), decoded.simm_I());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for S-type" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u3 = generate_common(u3);
    const _u12 = generate_common(u12);

    for (_u12) |_imm| {
        for (_u5) |_rs2| {
            for (_u5) |_rs1| {
                for (_u3) |_funct3| {
                    for (_u7) |_opcode| {
                        var fields: SFields = .{
                            .opcode = _opcode,
                            .imm_04_00 = 0,
                            .funct3 = _funct3,
                            .rs1 = _rs1,
                            .rs2 = _rs2,
                            .imm_11_05 = 0,
                        };

                        fields.set_imm(_imm);

                        const raw = get_raw(fields);
                        const decoded: Self = .{ .raw = raw };

                        try expectEqual(fields.get_imm(), decoded.imm_S());
                        try expectEqual(fields.rs2, decoded.rs2());
                        try expectEqual(fields.rs1, decoded.rs1());
                        try expectEqual(fields.funct3, decoded.funct3());
                        try expectEqual(fields.opcode, decoded.opcode());

                        const signed_imm: i12 = @bitCast(decoded.imm_S());
                        try expectEqual(@as(i64, signed_imm), decoded.simm_S());
                    }
                }
            }
        }
    }
}

test "Instruction: real S-type examples" {
    const instructions = [_]SFields{
        @bitCast(@as(u32, 0x00110023)), // sb x1, 0(x2)
        @bitCast(@as(u32, 0x003200A3)), // sb x3, 1(x4)
        @bitCast(@as(u32, 0xFE530FA3)), // sb x5, -1(x6)
        @bitCast(@as(u32, 0x7E740FA3)), // sb x7, 2047(x8)
        @bitCast(@as(u32, 0x80950023)), // sb x9, -2048(x10)
        @bitCast(@as(u32, 0x00B61023)), // sh x11, 0(x12)
        @bitCast(@as(u32, 0x00D71123)), // sh x13, 2(x14)
        @bitCast(@as(u32, 0xFEF81F23)), // sh x15, -2(x16)
        @bitCast(@as(u32, 0x41191023)), // sh x17, 1024(x18)
        @bitCast(@as(u32, 0xC13A1023)), // sh x19, -1024(x20)
        @bitCast(@as(u32, 0x015B2023)), // sw x21, 0(x22)
        @bitCast(@as(u32, 0x017C2223)), // sw x23, 4(x24)
        @bitCast(@as(u32, 0xFF9D2E23)), // sw x25, -4(x26)
        @bitCast(@as(u32, 0x21BE2023)), // sw x27, 512(x28)
        @bitCast(@as(u32, 0xE1DF2023)), // sw x29, -512(x30)
        @bitCast(@as(u32, 0x01F0B023)), // sd x31, 0(x1)
        @bitCast(@as(u32, 0x0021B423)), // sd x2, 8(x3)
        @bitCast(@as(u32, 0xFE42BC23)), // sd x4, -8(x5)
        @bitCast(@as(u32, 0x7E63BFA3)), // sd x6, 2047(x7)
        @bitCast(@as(u32, 0x8084B023)), // sd x8, -2048(x9)
    };

    // one manual test for first instruction
    const raw_manual: u32 = get_raw(instructions[0]);
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(35, decoded_manual.opcode());
    try expectEqual(0, decoded_manual.funct3());
    try expectEqual(2, decoded_manual.rs1());
    try expectEqual(1, decoded_manual.rs2());
    try expectEqual(0, decoded_manual.imm_S());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(inst.opcode, decoded.opcode());
        try expectEqual(inst.funct3, decoded.funct3());
        try expectEqual(inst.rs1, decoded.rs1());
        try expectEqual(inst.rs2, decoded.rs2());
        try expectEqual(inst.get_imm(), decoded.imm_S());

        const signed_imm: i12 = @bitCast(decoded.imm_S());
        try expectEqual(@as(i64, signed_imm), decoded.simm_S());
    }
}

test "Instruction: randomized S-types fields" {
    var prng = std.Random.DefaultPrng.init(0xDEADFEED);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: SFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(fields.opcode, decoded.opcode());
        try expectEqual(fields.funct3, decoded.funct3());
        try expectEqual(fields.rs1, decoded.rs1());
        try expectEqual(fields.rs2, decoded.rs2());
        try expectEqual(fields.get_imm(), decoded.imm_S());

        const signed_imm: i12 = @bitCast(decoded.imm_S());
        try expectEqual(@as(i64, signed_imm), decoded.simm_S());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for B-type" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u3 = generate_common(u3);
    const _u13 = generate_common(u13);

    // B-type clears the last 1 bit
    const IMM_MASK: u13 = 0x1;

    for (_u13) |_imm| {
        for (_u5) |_rs2| {
            for (_u5) |_rs1| {
                for (_u3) |_funct3| {
                    for (_u7) |_opcode| {
                        var fields: BFields = .{
                            .opcode = _opcode,
                            .imm_11_11 = 0,
                            .imm_04_01 = 0,
                            .funct3 = _funct3,
                            .rs1 = _rs1,
                            .rs2 = _rs2,
                            .imm_10_05 = 0,
                            .imm_12_12 = 0,
                        };

                        fields.set_imm(_imm);

                        const raw = get_raw(fields);
                        const decoded: Self = .{ .raw = raw };

                        try expectEqual(0, decoded.imm_B() & IMM_MASK);

                        try expectEqual(fields.get_imm(), decoded.imm_B());
                        try expectEqual(fields.rs2, decoded.rs2());
                        try expectEqual(fields.rs1, decoded.rs1());
                        try expectEqual(fields.funct3, decoded.funct3());
                        try expectEqual(fields.opcode, decoded.opcode());

                        const signed_imm: i13 = @bitCast(decoded.imm_B());
                        try expectEqual(@as(i64, signed_imm), decoded.simm_B());
                    }
                }
            }
        }
    }
}

test "Instruction: real B-type examples" {
    // B-type clears the last 1 bit
    const IMM_MASK: u13 = 0x1;

    const instructions = [_]BFields{
        @bitCast(@as(u32, 0x00208063)), // beq  x1,  x2, 0
        @bitCast(@as(u32, 0x00418863)), // beq  x3,  x4, 16
        @bitCast(@as(u32, 0xFE6288E3)), // beq  x5,  x6, -16
        @bitCast(@as(u32, 0x7E838FE3)), // beq  x7,  x8, 4094
        @bitCast(@as(u32, 0x00A49163)), // bne  x9,  x10, 2
        @bitCast(@as(u32, 0xFEC59FE3)), // bne  x11, x12, -2
        @bitCast(@as(u32, 0x10E69063)), // bne  x13, x14, 256
        @bitCast(@as(u32, 0xF10790E3)), // bne  x15, x16, -256
        @bitCast(@as(u32, 0x0328C063)), // blt  x17, x18, 32
        @bitCast(@as(u32, 0xFF49C0E3)), // blt  x19, x20, -32
        @bitCast(@as(u32, 0x056AE063)), // bltu x21, x22, 64
        @bitCast(@as(u32, 0xFD8BE0E3)), // bltu x23, x24, -64
        @bitCast(@as(u32, 0x09ACD063)), // bge  x25, x26, 128
        @bitCast(@as(u32, 0xF9CDD0E3)), // bge  x27, x28, -128
        @bitCast(@as(u32, 0x21EEF063)), // bgeu x29, x30, 512
        @bitCast(@as(u32, 0xE01FF0E3)), // bgeu x31, x1, -512
        @bitCast(@as(u32, 0x7E310FE3)), // beq  x2,  x3, 4094
        @bitCast(@as(u32, 0x80521063)), // bne  x4,  x5, -4096
        @bitCast(@as(u32, 0x007340E3)), // blt  x6,  x7, 2048
        @bitCast(@as(u32, 0x809450E3)), // bge  x8,  x9, -2048
    };

    // one manual test for first instruction
    const raw_manual: u32 = get_raw(instructions[0]);
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(0, decoded_manual.imm_B() & IMM_MASK);

    try expectEqual(99, decoded_manual.opcode());
    try expectEqual(0, decoded_manual.funct3());
    try expectEqual(1, decoded_manual.rs1());
    try expectEqual(2, decoded_manual.rs2());
    try expectEqual(0, decoded_manual.imm_B());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(0, decoded.imm_B() & IMM_MASK);

        try expectEqual(inst.opcode, decoded.opcode());
        try expectEqual(inst.funct3, decoded.funct3());
        try expectEqual(inst.rs1, decoded.rs1());
        try expectEqual(inst.rs2, decoded.rs2());
        try expectEqual(inst.get_imm(), decoded.imm_B());

        const signed_imm: i13 = @bitCast(decoded.imm_B());
        try expectEqual(@as(i64, signed_imm), decoded.simm_B());
    }
}

test "Instruction: randomized B-types fields" {
    // B-type clears the last 1 bit
    const IMM_MASK: u13 = 0x1;

    var prng = std.Random.DefaultPrng.init(0xFEEDDEAD);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: BFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(0, decoded.imm_B() & IMM_MASK);

        try expectEqual(fields.opcode, decoded.opcode());
        try expectEqual(fields.funct3, decoded.funct3());
        try expectEqual(fields.rs1, decoded.rs1());
        try expectEqual(fields.rs2, decoded.rs2());
        try expectEqual(fields.get_imm(), decoded.imm_B());

        const signed_imm: i13 = @bitCast(decoded.imm_B());
        try expectEqual(@as(i64, signed_imm), decoded.simm_B());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for U-type" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u32 = generate_common(u32);

    // U-type clears the last 12 bits
    const IMM_MASK: u32 = 0xFFF;

    for (_u32) |_imm| {
        for (_u5) |_rd| {
            for (_u7) |_opcode| {
                var fields: UFields = .{
                    .opcode = _opcode,
                    .rd = _rd,
                    .imm_31_12 = 0,
                };

                fields.set_imm(_imm);

                const raw = get_raw(fields);
                const decoded: Self = .{ .raw = raw };

                try expectEqual(0, decoded.imm_U() & IMM_MASK);

                try expectEqual(fields.get_imm(), decoded.imm_U());
                try expectEqual(fields.rd, decoded.rd());
                try expectEqual(fields.opcode, decoded.opcode());

                const signed_imm: i32 = @bitCast(decoded.imm_U());
                try expectEqual(@as(i64, signed_imm), decoded.simm_U());
            }
        }
    }
}

test "Instruction: real U-type examples" {
    // U-type clears the last 12 bits
    const IMM_MASK: u32 = 0xFFF;

    const instructions = [_]UFields{
        @bitCast(@as(u32, 0x000000B7)), // lui   x1, 0
        @bitCast(@as(u32, 0x00001137)), // lui   x2, 1
        @bitCast(@as(u32, 0x123451B7)), // lui   x3, 0x12345
        @bitCast(@as(u32, 0x7FFFF237)), // lui   x4, 0x7FFFF
        @bitCast(@as(u32, 0x800002B7)), // lui   x5, 0x80000
        @bitCast(@as(u32, 0xFFFFF337)), // lui   x6, 0xFFFFF
        @bitCast(@as(u32, 0x00000397)), // auipc x7, 0
        @bitCast(@as(u32, 0x00001417)), // auipc x8, 1
        @bitCast(@as(u32, 0x12345497)), // auipc x9, 0x12345
        @bitCast(@as(u32, 0x7FFFF517)), // auipc x10, 0x7FFFF
        @bitCast(@as(u32, 0x80000597)), // auipc x11, 0x80000
        @bitCast(@as(u32, 0xFFFFF617)), // auipc x12, 0xFFFFF
    };

    // one manual test for first instruction
    const raw_manual: u32 = get_raw(instructions[0]);
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(0, decoded_manual.imm_U() & IMM_MASK);

    try expectEqual(55, decoded_manual.opcode());
    try expectEqual(1, decoded_manual.rd());
    try expectEqual(0, decoded_manual.imm_U());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(0, decoded.imm_U() & IMM_MASK);

        try expectEqual(inst.opcode, decoded.opcode());
        try expectEqual(inst.rd, decoded.rd());
        try expectEqual(inst.get_imm(), decoded.imm_U());

        const signed_imm: i32 = @bitCast(decoded.imm_U());
        try expectEqual(@as(i64, signed_imm), decoded.simm_U());
    }
}

test "Instruction: randomized U-types fields" {
    // U-type clears the last 12 bits
    const IMM_MASK: u32 = 0xFFF;

    var prng = std.Random.DefaultPrng.init(0xFACEDEAD);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: UFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(0, decoded.imm_U() & IMM_MASK);

        try expectEqual(fields.opcode, decoded.opcode());
        try expectEqual(fields.rd, decoded.rd());
        try expectEqual(fields.get_imm(), decoded.imm_U());

        const signed_imm: i32 = @bitCast(decoded.imm_U());
        try expectEqual(@as(i64, signed_imm), decoded.simm_U());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for J-type" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u21 = generate_common(u21);

    // J-type clears the last 1 bit
    const IMM_MASK: u21 = 0x1;

    for (_u21) |_imm| {
        for (_u5) |_rd| {
            for (_u7) |_opcode| {
                var fields: JFields = .{
                    .opcode = _opcode,
                    .rd = _rd,
                    .imm_10_01 = 0,
                    .imm_11_11 = 0,
                    .imm_19_12 = 0,
                    .imm_20_20 = 0,
                };

                fields.set_imm(_imm);

                const raw = get_raw(fields);
                const decoded: Self = .{ .raw = raw };

                try expectEqual(0, decoded.imm_J() & IMM_MASK);

                try expectEqual(fields.get_imm(), decoded.imm_J());
                try expectEqual(fields.rd, decoded.rd());
                try expectEqual(fields.opcode, decoded.opcode());

                const signed_imm: i21 = @bitCast(decoded.imm_J());
                try expectEqual(@as(i64, signed_imm), decoded.simm_J());
            }
        }
    }
}

test "Instruction: real J-type examples" {
    // J-type clears the last 1 bit
    const IMM_MASK: u21 = 0x1;

    const instructions = [_]JFields{
        @bitCast(@as(u32, 0x0000006F)), // jal x0, 0
        @bitCast(@as(u32, 0x002000EF)), // jal x1, 2
        @bitCast(@as(u32, 0x0040016F)), // jal x2, 4
        @bitCast(@as(u32, 0x00A001EF)), // jal x3, 10
        @bitCast(@as(u32, 0x0540026F)), // jal x4, 84
        @bitCast(@as(u32, 0x080002EF)), // jal x5, 128
        @bitCast(@as(u32, 0x1000036F)), // jal x6, 256
        @bitCast(@as(u32, 0x200003EF)), // jal x7, 512
        @bitCast(@as(u32, 0x4000046F)), // jal x8, 1024
        @bitCast(@as(u32, 0x000014EF)), // jal x9, 4096
        @bitCast(@as(u32, 0xFFFFF56F)), // jal x10, -2
        @bitCast(@as(u32, 0xFFDFF5EF)), // jal x11, -4
        @bitCast(@as(u32, 0xFF7FF66F)), // jal x12, -10
        @bitCast(@as(u32, 0xFADFF6EF)), // jal x13, -84
        @bitCast(@as(u32, 0xF81FF76F)), // jal x14, -128
        @bitCast(@as(u32, 0xF01FF7EF)), // jal x15, -256
        @bitCast(@as(u32, 0xE01FF86F)), // jal x16, -512
        @bitCast(@as(u32, 0xC01FF8EF)), // jal x17, -1024
        @bitCast(@as(u32, 0x7FFFF96F)), // jal x18, 1048574
        @bitCast(@as(u32, 0x800009EF)), // jal x19, -1048576
    };


    // one manual test for first instruction
    const raw_manual: u32 = get_raw(instructions[0]);
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(0, decoded_manual.imm_J() & IMM_MASK);

    try expectEqual(111, decoded_manual.opcode());
    try expectEqual(0, decoded_manual.rd());
    try expectEqual(0, decoded_manual.imm_J());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(0, decoded.imm_J() & IMM_MASK);

        try expectEqual(inst.opcode, decoded.opcode());
        try expectEqual(inst.rd, decoded.rd());
        try expectEqual(inst.get_imm(), decoded.imm_J());

        const signed_imm: i21 = @bitCast(decoded.imm_J());
        try expectEqual(@as(i64, signed_imm), decoded.simm_J());
    }
}

test "Instruction: randomized J-types fields" {
    // J-type clears the last 1 bit
    const IMM_MASK: u21 = 0x1;

    var prng = std.Random.DefaultPrng.init(0xF00DDEAD);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: JFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(0, decoded.imm_J() & IMM_MASK);

        try expectEqual(fields.opcode, decoded.opcode());
        try expectEqual(fields.rd, decoded.rd());
        try expectEqual(fields.get_imm(), decoded.imm_J());

        const signed_imm: i21 = @bitCast(decoded.imm_J());
        try expectEqual(@as(i64, signed_imm), decoded.simm_J());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for shamt (RV64I shift-imm)" {
    const _u7 = generate_common(u7);
    const _u6 = generate_common(u6);
    const _u5 = generate_common(u5);
    const _u3 = generate_common(u3);

    for (_u6) |_funct6| {
        for (_u6) |_shamt| {
            for (_u5) |_rs1| {
                for (_u3) |_funct3| {
                    for (_u5) |_rd| {
                        for (_u7) |_opcode| {
                            const fields: ShiftIFields = .{
                                .opcode = _opcode,
                                .rd = _rd,
                                .funct3 = _funct3,
                                .rs1 = _rs1,
                                .shamt = _shamt,
                                .funct6 = _funct6,
                            };

                            const raw = get_raw(fields);
                            const decoded: Self = .{ .raw = raw };

                            try expectEqual(fields.funct6, decoded.funct6());
                            try expectEqual(fields.shamt, decoded.shamt());
                            try expectEqual(fields.rs1, decoded.rs1());
                            try expectEqual(fields.funct3, decoded.funct3());
                            try expectEqual(fields.rd, decoded.rd());
                            try expectEqual(fields.opcode, decoded.opcode());
                        }
                    }
                }
            }
        }
    }
}

test "Instruction: real RV64I shift-immediate examples (shamt >= 32 included)" {
    const instructions = [_]ShiftIFields{
        @bitCast(@as(u32, 0x00119113)), // slli x2, x3, 1
        @bitCast(@as(u32, 0x03F29213)), // slli x4, x5, 63
        @bitCast(@as(u32, 0x0083D313)), // srli x6, x7, 8
        @bitCast(@as(u32, 0x41F4D413)), // srai x8, x9, 31
        @bitCast(@as(u32, 0x02015513)), // srli x10, x2, 32
        @bitCast(@as(u32, 0x0201D613)), // srli x12, x3, 32
    };

    // one manual check
    const raw_manual: u32 = get_raw(instructions[1]);
    const decoded_manual: Self = .{ .raw = raw_manual };
    try expectEqual(63, decoded_manual.shamt());

    for (instructions) |inst| {
        const raw: u32 = get_raw(inst);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(inst.funct6, decoded.funct6());
        try expectEqual(inst.shamt, decoded.shamt());
        try expectEqual(inst.rs1, decoded.rs1());
        try expectEqual(inst.funct3, decoded.funct3());
        try expectEqual(inst.rd, decoded.rd());
        try expectEqual(inst.opcode, decoded.opcode());
    }
}

test "Instruction: randomized shamt fields" {
    var prng = std.Random.DefaultPrng.init(0xBEADF00D);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const fields: ShiftIFields = @bitCast(raw);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(fields.funct6, decoded.funct6());
        try expectEqual(fields.shamt, decoded.shamt());
        try expectEqual(fields.rs1, decoded.rs1());
        try expectEqual(fields.funct3, decoded.funct3());
        try expectEqual(fields.rd, decoded.rd());
        try expectEqual(fields.opcode, decoded.opcode());
    }
}

test "Instruction: 0, 1, max, max - 1, mid and boundary values for csr()" {
    const _u7 = generate_common(u7);
    const _u5 = generate_common(u5);
    const _u3 = generate_common(u3);
    const _u12 = generate_common(u12);

    for (_u12) |_imm| {
        for (_u5) |_rs1| {
            for (_u3) |_funct3| {
                for (_u5) |_rd| {
                    for (_u7) |_opcode| {
                        var fields: IFields = .{
                            .opcode = _opcode,
                            .rd = _rd,
                            .funct3 = _funct3,
                            .rs1 = _rs1,
                            .imm_11_00 = 0,
                        };

                        fields.set_imm(_imm);

                        const raw = get_raw(fields);
                        const decoded: Self = .{ .raw = raw };

                        try expectEqual(decoded.imm_I(), decoded.csr());
                        try expectEqual(fields.get_imm(), decoded.csr());
                    }
                }
            }
        }
    }
}

test "Instruction: real CSR instruction examples" {
    const raw_manual: u32 = 0x30011173; // csrrw x2, mstatus(0x300), x2
    const decoded_manual: Self = .{ .raw = raw_manual };

    try expectEqual(0x300, decoded_manual.csr());
    try expectEqual(1, decoded_manual.funct3());
    try expectEqual(2, decoded_manual.rs1());
    try expectEqual(2, decoded_manual.rd());
    try expectEqual(115, decoded_manual.opcode());

    const instructions = [_]u32{
        0x30011173, // csrrw x2,  mstatus, x2
        0x00102573, // csrrs x10, 0x001 (fflags), x0
        0xFFF03073, // csrrc x0,  0xFFF, x0
    };

    for (instructions) |raw| {
        const decoded: Self = .{ .raw = raw };
        try expectEqual(decoded.imm_I(), decoded.csr());
    }
}

test "Instruction: randomized csr() vs imm_I() agreement" {
    var prng = std.Random.DefaultPrng.init(0xDEADBEAD);
    const random = prng.random();

    for (0..10000) |_| {
        const raw = random.int(u32);
        const decoded: Self = .{ .raw = raw };

        try expectEqual(decoded.imm_I(), decoded.csr());
    }
}
