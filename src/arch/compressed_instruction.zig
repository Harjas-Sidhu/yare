const std = @import("std");
const Instruction = @import("instruction.zig");
const sign_extend = @import("sign_extend.zig").sign_extend;
const assert = std.debug.assert;

// RV64C + D
pub const UNCOMPRESSED_QUADRANT: u2 = 0b11;

// HINTs are expanded to HINTs
// 0 is illegal in both full and compressed instruction format.
const ILLEGAL_INSTRUCTION: u32 = 0;

const CDispatchKey = enum(u5) {
    // quadrant 0
    addi4spn_illegal = 0b00000,
    fld = 0b00100,
    lw = 0b01000,
    ld = 0b01100,
    fsd = 0b10100,
    sw = 0b11000,
    sd = 0b11100,

    // quadrant 1
    nop_addi = 0b00001,
    addiw = 0b00101,
    li = 0b01001,
    addi16sp_lui = 0b01101,
    alu = 0b10001,
    j = 0b10101,
    beqz = 0b11001,
    bnez = 0b11101,

    // quadrant 2
    slli = 0b00010,
    fldsp = 0b00110,
    lwsp = 0b01010,
    ldsp = 0b01110,
    system_jump_add = 0b10010,
    fsdsp = 0b10110,
    swsp = 0b11010,
    sdsp = 0b11110,

    // un-mapped values
    _,
};

inline fn decompress_register(compressed_register: u3) u5 {
    return @as(u5, compressed_register) + 8;
}

// funct3 | quadrant
inline fn create_dispatch_key(funct3: u3, quadrant: u2) CDispatchKey {
    const dispatch_key: u5 = @as(u5, funct3) << 2 | quadrant;
    return @enumFromInt(dispatch_key);
}

pub fn decompress(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    assert(quadrant != UNCOMPRESSED_QUADRANT);

    const dispatch_key = create_dispatch_key(funct3, quadrant);

    return switch (dispatch_key) {
        .addi4spn_illegal => ADDI: {
            if (compressed_instruction == 0) break :ADDI ILLEGAL_INSTRUCTION;
            break :ADDI decompress_addi4spn(compressed_instruction);
        },
        .fld => decompress_fld(compressed_instruction),
        .lw => decompress_lw(compressed_instruction),
        .ld => decompress_ld(compressed_instruction),
        .fsd => decompress_fsd(compressed_instruction),
        .sw => decompress_sw(compressed_instruction),
        .sd => decompress_sd(compressed_instruction),

        .nop_addi => decompress_nop_addi(compressed_instruction),
        .addiw => decompress_addiw(compressed_instruction),
        .li => decompress_li(compressed_instruction),
        .addi16sp_lui => decompress_addi16sp_lui(compressed_instruction),
        .alu => decompress_alu(compressed_instruction),
        .j => decompress_j(compressed_instruction),
        .beqz => decompress_beqz(compressed_instruction),
        .bnez => decompress_bnez(compressed_instruction),

        .slli => decompress_slli(compressed_instruction),
        .fldsp => decompress_fldsp(compressed_instruction),
        .lwsp => decompress_lwsp(compressed_instruction),
        .ldsp => decompress_ldsp(compressed_instruction),
        .system_jump_add => decompress_system_jump_add(compressed_instruction),
        .fsdsp => decompress_fsdsp(compressed_instruction),
        .swsp => decompress_swsp(compressed_instruction),
        .sdsp => decompress_sdsp(compressed_instruction),

        else => return ILLEGAL_INSTRUCTION,
    };
}

// c.addi4spn | addi rd', x2, nzuimm | I-Type
// 000 | uimm[5:4] | uimm[9:6] | uimm[2] | uimm[3] | rd' | 00
inline fn decompress_addi4spn(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .addi4spn_illegal);

    const rd = decompress_register(@truncate(compressed_instruction >> 2));
    const uimm_2_2: u1 = @truncate(compressed_instruction >> 6);
    const uimm_3_3: u1 = @truncate(compressed_instruction >> 5);
    const uimm_5_4: u2 = @truncate(compressed_instruction >> 11);
    const uimm_9_6: u4 = @truncate(compressed_instruction >> 7);

    const uimm: u10 =
        @as(u10, uimm_9_6) << 6 |
        @as(u10, uimm_5_4) << 4 |
        @as(u10, uimm_3_3) << 3 |
        @as(u10, uimm_2_2) << 2;

    if (uimm == 0) return ILLEGAL_INSTRUCTION;

    var instruction: Instruction.IFields = .{
        .opcode = 0x13,
        .rd = rd,
        .funct3 = 0x0,
        .rs1 = 0x2,
        .imm_11_00 = 0x0,
    };

    instruction.set_imm(uimm);
    return @bitCast(instruction);
}

// c.fld | fld rd', offset(rs1') | I-Type
// 001 | uimm[5:3] | rs1' | uimm[7:6] | rd' | 00
inline fn decompress_fld(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .fld);

    const rd = decompress_register(@truncate(compressed_instruction >> 2));
    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));

    var instruction: Instruction.IFields = .{
        .opcode = 0x07,
        .rd = rd,
        .funct3 = 0x3,
        .rs1 = rs1,
        .imm_11_00 = 0x0,
    };

    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 5);

    const imm: u8 =
        @as(u8, imm_07_06) << 6 |
        @as(u8, imm_05_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.lw | lw rd', offset(rs1') | I-Type
// 010 | uimm[5:3] | rs1' | uimm[2] | uimm[6] | rd' | 00
inline fn decompress_lw(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .lw);

    const rd = decompress_register(@truncate(compressed_instruction >> 2));
    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));

    var instruction: Instruction.IFields = .{
        .opcode = 0x3,
        .rd = rd,
        .funct3 = 0x2,
        .rs1 = rs1,
        .imm_11_00 = 0x0,
    };

    const imm_02_02: u1 = @truncate(compressed_instruction >> 6);
    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_06_06: u1 = @truncate(compressed_instruction >> 5);

    const imm: u7 =
        @as(u7, imm_06_06) << 6 |
        @as(u7, imm_05_03) << 3 |
        @as(u7, imm_02_02) << 2;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.ld | ld rd', offset(rs1') | I-Type
// 011 | uimm[5:3] | rs1' | uimm[7:6] | rd' | 00
inline fn decompress_ld(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .ld);

    const rd = decompress_register(@truncate(compressed_instruction >> 2));
    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));

    var instruction: Instruction.IFields = .{
        .opcode = 0x3,
        .rd = rd,
        .funct3 = 0x3,
        .rs1 = rs1,
        .imm_11_00 = 0x0,
    };

    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 5);

    const imm: u8 =
        @as(u8, imm_07_06) << 6 |
        @as(u8, imm_05_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.fsd | fsd rs2', offset(rs1') | S-Type
// 101 | uimm[5:3] | rs1' | uimm[7:6] | rs2' | 00
inline fn decompress_fsd(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .fsd);

    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));
    const rs2 = decompress_register(@truncate(compressed_instruction >> 2));

    var instruction: Instruction.SFields = .{
        .opcode = 0x27,
        .imm_04_00 = 0x0,
        .funct3 = 0x3,
        .rs1 = rs1,
        .rs2 = rs2,
        .imm_11_05 = 0x0,
    };

    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 5);

    const imm: u8 =
        @as(u8, imm_07_06) << 6 |
        @as(u8, imm_05_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.sw | sw rs2', offset(rs1') | S-Type
// 110 | uimm[5:3] | rs1' | uimm[2] | uimm[6] | rd' | 00
inline fn decompress_sw(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .sw);

    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));
    const rs2 = decompress_register(@truncate(compressed_instruction >> 2));

    var instruction: Instruction.SFields = .{
        .opcode = 0x23,
        .imm_04_00 = 0x0,
        .funct3 = 0x2,
        .rs1 = rs1,
        .rs2 = rs2,
        .imm_11_05 = 0x0,
    };

    const imm_02_02: u1 = @truncate(compressed_instruction >> 6);
    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_06_06: u1 = @truncate(compressed_instruction >> 5);

    const imm: u7 =
        @as(u7, imm_06_06) << 6 |
        @as(u7, imm_05_03) << 3 |
        @as(u7, imm_02_02) << 2;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.sd | sd rs2', offset(rs1') | S-Type
// 111 | uimm[5:3] | rs1' | uimm[7:6] | rd' | 00
inline fn decompress_sd(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .sd);

    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));
    const rs2 = decompress_register(@truncate(compressed_instruction >> 2));

    var instruction: Instruction.SFields = .{
        .opcode = 0x23,
        .imm_04_00 = 0x0,
        .funct3 = 0x3,
        .rs1 = rs1,
        .rs2 = rs2,
        .imm_11_05 = 0x0,
    };

    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 5);

    const imm: u8 =
        @as(u8, imm_07_06) << 6 |
        @as(u8, imm_05_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.nop | addi 0, 0, 0 | I-Type
// 000 | imm[5] | 00000 | imm[4:0] | 01

// c.addi | addi rd, rd, imm | I-Type
// 000 | imm[5] | rs1/rd != 0 | imm[4:0] | 01
inline fn decompress_nop_addi(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .nop_addi);

    const rd: u5 = @truncate(compressed_instruction >> 7);

    var instruction: Instruction.IFields = .{
        .opcode = 0x13,
        .rd = rd,
        .funct3 = 0x0,
        .rs1 = rd,
        .imm_11_00 = 0x0,
    };

    const imm_04_00: u5 = @truncate(compressed_instruction >> 2);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);

    const imm: u6 =
        @as(u6, imm_05_05) << 5 |
        @as(u6, imm_04_00);

    const simm: i12 = @truncate(sign_extend(imm));

    instruction.set_imm(@bitCast(simm));
    return @bitCast(instruction);
}

// c.addiw | addiw rd, rd, imm | I-Type
// 001 | imm[5] | rs1/rd != 0 | imm[4:0] | 01 - { RESERVED: rs1/rd = 0 }
inline fn decompress_addiw(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .addiw);

    const rd: u5 = @truncate(compressed_instruction >> 7);
    if (rd == 0) return ILLEGAL_INSTRUCTION;

    var instruction: Instruction.IFields = .{
        .opcode = 0x1B,
        .rd = rd,
        .funct3 = 0x0,
        .rs1 = rd,
        .imm_11_00 = 0x0,
    };

    const imm_04_00: u5 = @truncate(compressed_instruction >> 2);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);

    const imm: u6 =
        @as(u6, imm_05_05) << 5 |
        @as(u6, imm_04_00);

    const simm: i12 = @truncate(sign_extend(imm));

    instruction.set_imm(@bitCast(simm));
    return @bitCast(instruction);
}

// c.li | addi rd, x0, imm | I-Type
// 010 | imm[5] | rd != 0 | imm[4:0] | 01 - { HINT: rd == 0 }
inline fn decompress_li(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .li);

    const rd: u5 = @truncate(compressed_instruction >> 7);

    var instruction: Instruction.IFields = .{
        .opcode = 0x13,
        .rd = rd,
        .funct3 = 0x0,
        .rs1 = 0x0,
        .imm_11_00 = 0x0,
    };

    const imm_04_00: u5 = @truncate(compressed_instruction >> 2);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);

    const imm: u6 =
        @as(u6, imm_05_05) << 5 |
        @as(u6, imm_04_00);

    const simm: i12 = @truncate(sign_extend(imm));

    instruction.set_imm(@bitCast(simm));
    return @bitCast(instruction);
}

// c.addi16sp | addi x2, x2, nzimm | I-Type
// 011 | imm[9] | 00010 | imm[4] | imm[6] | imm[8:7] | imm[5] | 01 - { RESERVED: imm == 0 }

// c.lui | lui rd, nzimm | U-type
// 011 | imm[9] | rd != {0, 2} | imm[16:12] | 01 - { RESERVED: imm == 0 , HINT: rd == 0 }
inline fn decompress_addi16sp_lui(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .addi16sp_lui);

    const rd: u5 = @truncate(compressed_instruction >> 7);
    const imm_low: u5 = @truncate(compressed_instruction >> 2);
    const imm_high: u1 = @truncate(compressed_instruction >> 12);

    if (imm_low == 0 and imm_high == 0) return ILLEGAL_INSTRUCTION;

    if (rd == 2) { // c.addi16sp
        var instruction: Instruction.IFields = .{
            .opcode = 0x13,
            .rd = rd,
            .funct3 = 0x0,
            .rs1 = rd,
            .imm_11_00 = 0x0,
        };

        const imm_04_04: u1 = @truncate(imm_low >> 4);
        const imm_05_05: u1 = @truncate(imm_low);
        const imm_06_06: u1 = @truncate(imm_low >> 3);
        const imm_08_07: u2 = @truncate(imm_low >> 1);
        const imm_09_09: u1 = imm_high;

        const imm: u10 =
            @as(u10, imm_09_09) << 9 |
            @as(u10, imm_08_07) << 7 |
            @as(u10, imm_06_06) << 6 |
            @as(u10, imm_05_05) << 5 |
            @as(u10, imm_04_04) << 4;

        const simm: i12 = @truncate(sign_extend(imm));

        instruction.set_imm(@bitCast(simm));
        return @bitCast(instruction);
    } else { // c.lui
        const imm_16_12: u5 = imm_low;
        const imm_17_17: u1 = imm_high;

        const imm: u18 =
            @as(u18, imm_17_17) << 17 |
            @as(u18, imm_16_12) << 12;

        var instruction: Instruction.UFields = .{
            .opcode = 0x37,
            .rd = rd,
            .imm_31_12 = 0x0,
        };

        const simm: i32 = @truncate(sign_extend(imm));

        instruction.set_imm(@bitCast(simm));
        return @bitCast(instruction);
    }
}

const CALUPrimary = enum(u2) {
    srli = 0b00,
    srai = 0b01,
    andi = 0b10,

    register,
};

const CALUExtended = enum(u3) {
    // bit 12 = 0
    sub = 0b000,
    xor = 0b001,
    @"or" = 0b010,
    @"and" = 0b011,

    // bit 12 = 1
    subw = 0b100,
    addw = 0b101,

    // un-mapped
    _,
};

// c.srli | srli rd', rd', shamt | I-Type(Shift)
// 100 | uimm[5] | 00 | rs1'/rd' | uimm[4:0] | 01

// c.srai | srai rd', rd', shamt | I-Type (Shift)
// 100 | uimm[5] | 01 | rs1'/rd' | uimm[4:0] | 01

// c.andi | andi rd', rd', imm | I-Type
// 100 | uimm[5] | 10 | rs1'/rd' | uimm[4:0] | 01

// c.sub | sub rd', rd', rs2' | R-Type
// 100 | 0 | 11 | rs1'/rd' | 00 | rs2' | 01

// c.xor | xor rd', rd', rs2' | R-Type
// 100 | 0 | 11 | rs1'/rd' | 01 | rs2' | 01

// c.or | or rd', rd', rs2' | R-Type
// 100 | 0 | 11 | rs1'/rd' | 10 | rs2' | 01

// c.and | and rd', rd', rs2' | R-Type
// 100 | 0 | 11 | rs1'/rd' | 11 | rs2' | 01

// c.subw | subw rd', rd', rs2' | R-Type
// 100 | 1 | 00 | rs1'/rd' | 00 | rs2' | 01

// c.addw | addw rd', rd', rs2' | R-Type
// 100 | 1 | 01 | rs1'/rd' | 00 | rs2' | 01
inline fn decompress_alu(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .alu);

    const alu_primary: u2 = @truncate(compressed_instruction >> 10);
    const alu: CALUPrimary = @enumFromInt(alu_primary);

    const rd = decompress_register(@truncate(compressed_instruction >> 7));
    const imm_04_00: u5 = @truncate(compressed_instruction >> 2);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);

    const imm: u6 =
        @as(u6, imm_05_05) << 5 |
        @as(u6, imm_04_00);

    switch (alu) {
        .srli => {
            const instruction: Instruction.ShiftIFields = .{
                .opcode = 0x13,
                .rd = rd,
                .funct3 = 0x5,
                .rs1 = rd,
                .shamt = imm,
                .funct6 = 0x0,
            };

            return @bitCast(instruction);
        },
        .srai => {
            const instruction: Instruction.ShiftIFields = .{
                .opcode = 0x13,
                .rd = rd,
                .funct3 = 0x5,
                .rs1 = rd,
                .shamt = imm,
                .funct6 = 0x10,
            };

            return @bitCast(instruction);
        },
        .andi => {
            var instruction: Instruction.IFields = .{
                .opcode = 0x13,
                .rd = rd,
                .funct3 = 0x7,
                .rs1 = rd,
                .imm_11_00 = 0x0,
            };

            const simm: i12 = @truncate(sign_extend(imm));

            instruction.set_imm(@bitCast(simm));
            return @bitCast(instruction);
        },

        .register => {
            const rs2_funct2: u2 = @truncate(imm_04_00 >> 3);
            const alu_dispatch_key: u3 = @as(u3, imm_05_05) << 2 | rs2_funct2;

            const extended: CALUExtended = @enumFromInt(alu_dispatch_key);
            const rs2 = decompress_register(@truncate(imm_04_00));

            var instruction: Instruction.RFields = .{
                .opcode = 0x33,
                .rd = rd,
                .funct3 = 0x0,
                .rs1 = rd,
                .rs2 = rs2,
                .funct7 = 0x0,
            };

            switch (extended) {
                .sub => instruction.funct7 = 0x20,
                .xor => instruction.funct3 = 0x4,
                .@"or" => instruction.funct3 = 0x6,
                .@"and" => instruction.funct3 = 0x7,

                .subw => {
                    instruction.opcode = 0x3B;
                    instruction.funct7 = 0x20;
                },
                .addw => instruction.opcode = 0x3B,

                else => return ILLEGAL_INSTRUCTION,
            }

            return @bitCast(instruction);
        },
    }
}

// c.j | jal x0, offset | J-Type
// 101 | imm[11] | imm[4] | imm[9:8] | imm[10] | imm[6] | imm[7] | imm[3:1] imm[5] | 01
inline fn decompress_j(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .j);

    var instruction: Instruction.JFields = .{
        .opcode = 0x6F,
        .rd = 0x0,
        .imm_10_01 = 0x0,
        .imm_11_11 = 0x0,
        .imm_19_12 = 0x0,
        .imm_20_20 = 0x0,
    };

    const imm_03_01: u3 = @truncate(compressed_instruction >> 3);
    const imm_04_04: u1 = @truncate(compressed_instruction >> 11);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 2);
    const imm_06_06: u1 = @truncate(compressed_instruction >> 7);
    const imm_07_07: u1 = @truncate(compressed_instruction >> 6);
    const imm_09_08: u2 = @truncate(compressed_instruction >> 9);
    const imm_10_10: u1 = @truncate(compressed_instruction >> 8);
    const imm_11_11: u1 = @truncate(compressed_instruction >> 12);

    const imm: u12 =
        @as(u12, imm_11_11) << 11 |
        @as(u12, imm_10_10) << 10 |
        @as(u12, imm_09_08) << 8 |
        @as(u12, imm_07_07) << 7 |
        @as(u12, imm_06_06) << 6 |
        @as(u12, imm_05_05) << 5 |
        @as(u12, imm_04_04) << 4 |
        @as(u12, imm_03_01) << 1;

    const simm: i21 = @truncate(sign_extend(imm));

    instruction.set_imm(@bitCast(simm));
    return @bitCast(instruction);
}

// c.beqz | beq rs1', x0, offset | B-Type
// 110 | imm[8] | imm[4:3] | rs1' | imm[7:6] | imm[2:1] | imm[5] | 01
inline fn decompress_beqz(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .beqz);

    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));

    var instruction: Instruction.BFields = .{
        .opcode = 0x63,
        .imm_11_11 = 0x0,
        .imm_04_01 = 0x0,
        .funct3 = 0x0,
        .rs1 = rs1,
        .rs2 = 0x0,
        .imm_10_05 = 0x0,
        .imm_12_12 = 0x0,
    };

    const imm_02_01: u2 = @truncate(compressed_instruction >> 3);
    const imm_04_03: u2 = @truncate(compressed_instruction >> 10);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 2);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 5);
    const imm_08_08: u1 = @truncate(compressed_instruction >> 12);

    const imm: u9 =
        @as(u9, imm_08_08) << 8 |
        @as(u9, imm_07_06) << 6 |
        @as(u9, imm_05_05) << 5 |
        @as(u9, imm_04_03) << 3 |
        @as(u9, imm_02_01) << 1;

    const simm: i13 = @truncate(sign_extend(imm));

    instruction.set_imm(@bitCast(simm));
    return @bitCast(instruction);
}

// c.bnez | bne rs1', x0, offset | B-Type
// 111 | imm[8] | imm[4:3] | rs1' | imm[7:6] | imm[2:1] | imm[5] | 01
inline fn decompress_bnez(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .bnez);

    const rs1 = decompress_register(@truncate(compressed_instruction >> 7));

    var instruction: Instruction.BFields = .{
        .opcode = 0x63,
        .imm_11_11 = 0x0,
        .imm_04_01 = 0x0,
        .funct3 = 0x1,
        .rs1 = rs1,
        .rs2 = 0x0,
        .imm_10_05 = 0x0,
        .imm_12_12 = 0x0,
    };

    const imm_02_01: u2 = @truncate(compressed_instruction >> 3);
    const imm_04_03: u2 = @truncate(compressed_instruction >> 10);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 2);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 5);
    const imm_08_08: u1 = @truncate(compressed_instruction >> 12);

    const imm: u9 =
        @as(u9, imm_08_08) << 8 |
        @as(u9, imm_07_06) << 6 |
        @as(u9, imm_05_05) << 5 |
        @as(u9, imm_04_03) << 3 |
        @as(u9, imm_02_01) << 1;

    const simm: i13 = @truncate(sign_extend(imm));

    instruction.set_imm(@bitCast(simm));
    return @bitCast(instruction);
}

// c.slli | slli rd, rd, shamt | I-Type (Shift)
// 000 | nzuimm[5] | rs1/rd != 0 | nzuimm[4:0] | 10 | - { HINT: imm == 0, rs1/rd == 0 }
inline fn decompress_slli(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .slli);

    const rd: u5 = @truncate(compressed_instruction >> 7);
    const shamt_04_00: u5 = @truncate(compressed_instruction >> 2);
    const shamt_05_05: u1 = @truncate(compressed_instruction >> 12);

    const shamt: u6 =
        @as(u6, shamt_05_05) << 5 |
        @as(u6, shamt_04_00);

    const instruction: Instruction.ShiftIFields = .{
        .opcode = 0x13,
        .rd = rd,
        .funct3 = 0x1,
        .rs1 = rd,
        .shamt = shamt,
        .funct6 = 0x0,
    };

    return @bitCast(instruction);
}

// c.fldsp | fld rd, offset(x2) | I-Type
// 001 | uimm[5] | rd | uimm[4:3] | uimm[8:6] | 10
inline fn decompress_fldsp(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .fldsp);

    const rd: u5 = @truncate(compressed_instruction >> 7);

    var instruction: Instruction.IFields = .{
        .opcode = 0x7,
        .rd = rd,
        .funct3 = 0x3,
        .rs1 = 0x2,
        .imm_11_00 = 0x0,
    };

    const imm_04_03: u2 = @truncate(compressed_instruction >> 5);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);
    const imm_08_06: u3 = @truncate(compressed_instruction >> 2);

    const imm: u9 =
        @as(u9, imm_08_06) << 6 |
        @as(u9, imm_05_05) << 5 |
        @as(u9, imm_04_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.lwsp | lw rd, offset(x2) | I-Type
// 010 | uimm[5] | rd != 0 | uimm[4:2] | uimm[7:6] | 10 - { RESERVED: rd == 0 }
inline fn decompress_lwsp(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .lwsp);

    const rd: u5 = @truncate(compressed_instruction >> 7);
    if (rd == 0) return ILLEGAL_INSTRUCTION;

    var instruction: Instruction.IFields = .{
        .opcode = 0x3,
        .rd = rd,
        .funct3 = 0x2,
        .rs1 = 0x2,
        .imm_11_00 = 0x0,
    };

    const imm_04_02: u3 = @truncate(compressed_instruction >> 4);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 2);

    const imm: u8 =
        @as(u8, imm_07_06) << 6 |
        @as(u8, imm_05_05) << 5 |
        @as(u8, imm_04_02) << 2;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.ldsp | ld rd, offset(x2) | I-Type
// 011 | uimm[5] | rd != 0 | uimm[4:3] | uimm[8:6] | 10 - { RESERVED: rd == 0 }
inline fn decompress_ldsp(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .ldsp);

    const rd: u5 = @truncate(compressed_instruction >> 7);
    if (rd == 0) return ILLEGAL_INSTRUCTION;

    var instruction: Instruction.IFields = .{
        .opcode = 0x3,
        .rd = rd,
        .funct3 = 0x3,
        .rs1 = 0x2,
        .imm_11_00 = 0x0,
    };

    const imm_04_03: u2 = @truncate(compressed_instruction >> 5);
    const imm_05_05: u1 = @truncate(compressed_instruction >> 12);
    const imm_08_06: u3 = @truncate(compressed_instruction >> 2);

    const imm: u9 =
        @as(u9, imm_08_06) << 6 |
        @as(u9, imm_05_05) << 5 |
        @as(u9, imm_04_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

const CBit12 = enum(u1) {
    clear = 0,
    set = 1,
};

// c.jr | jalr x0, 0(rs1) | I-Type
// 100 | 0 | rs1 != 0 | 00000 | 10

// c.mv | add rd, x0, rs2 | R-Type
// 100 | 0 | rd != 0 | rs2 != 0 | 10

// c.ebreak | ebreak | I-Type (SYSTEM)
// 100 | 1 | 00000 | 00000 | 10

// c.jalr | jalr x1, 0(rs1) | I-Type
// 100 | 1 | rs1 != 0 | 00000 | 10

// c.add | add rd, rd, rs2 | R-Type
// 100 | 1 | rs1/rd != 0 | rs2 != 0 | 10
inline fn decompress_system_jump_add(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .system_jump_add);

    const rd: u5 = @truncate(compressed_instruction >> 7);
    const rs2: u5 = @truncate(compressed_instruction >> 2);

    const bit_12: u1 = @truncate(compressed_instruction >> 12);
    const system: CBit12 = @enumFromInt(bit_12);

    switch (system) {
        .clear => {
            if (rs2 == 0) { // jr
                if (rd == 0) return ILLEGAL_INSTRUCTION;

                const instruction: Instruction.IFields = .{
                    .opcode = 0x67,
                    .rd = 0x0,
                    .funct3 = 0x0,
                    .rs1 = rd,
                    .imm_11_00 = 0x0,
                };

                return @bitCast(instruction);
            } else { // mv
                const instruction: Instruction.RFields = .{
                    .opcode = 0x33,
                    .rd = rd,
                    .funct3 = 0x0,
                    .rs1 = 0x0,
                    .rs2 = rs2,
                    .funct7 = 0x0,
                };

                return @bitCast(instruction);
            }
        },
        .set => {
            if (rs2 == 0) { // ebreak_jalr
                if (rd == 0) { // ebreak
                    const instruction: Instruction.IFields = .{
                        .opcode = 0x73,
                        .rd = 0x0,
                        .funct3 = 0x0,
                        .rs1 = 0x0,
                        .imm_11_00 = 0x1,
                    };

                    return @bitCast(instruction);
                } else { // jalr

                    // NB: c.jalr expands to jalr, but its architectural pc increment is +2,
                    // not +4. The central dispatch must therefore use the compressed instruction
                    // length when advancing pc; do not treat this as an ordinary jalr.
                    const instruction: Instruction.IFields = .{
                        .opcode = 0x67,
                        .rd = 0x1,
                        .funct3 = 0x0,
                        .rs1 = rd,
                        .imm_11_00 = 0x0,
                    };

                    return @bitCast(instruction);
                }
            } else { // add
                const instruction: Instruction.RFields = .{
                    .opcode = 0x33,
                    .rd = rd,
                    .funct3 = 0x0,
                    .rs1 = rd,
                    .rs2 = rs2,
                    .funct7 = 0x0,
                };

                return @bitCast(instruction);
            }
        },
    }
}

// c.fsdsp | fsd rs2, offset(x2) | S-Type
// 101 | uimm[5:3] | uimm[8:6] | rs2 | 10
inline fn decompress_fsdsp(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .fsdsp);

    const rs2: u5 = @truncate(compressed_instruction >> 2);

    var instruction: Instruction.SFields = .{
        .opcode = 0x27,
        .imm_04_00 = 0x0,
        .funct3 = 0x3,
        .rs1 = 0x2,
        .rs2 = rs2,
        .imm_11_05 = 0x0,
    };

    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_08_06: u3 = @truncate(compressed_instruction >> 7);

    const imm: u9 =
        @as(u9, imm_08_06) << 6 |
        @as(u9, imm_05_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.swsp | sw rs2, offset(x2) | S-Type
// 110 | uimm[5:2] | uimm[7:6] | rs2 | 10
inline fn decompress_swsp(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .swsp);

    const rs2: u5 = @truncate(compressed_instruction >> 2);

    var instruction: Instruction.SFields = .{
        .opcode = 0x23,
        .imm_04_00 = 0x0,
        .funct3 = 0x2,
        .rs1 = 0x2,
        .rs2 = rs2,
        .imm_11_05 = 0x0,
    };

    const imm_05_02: u4 = @truncate(compressed_instruction >> 9);
    const imm_07_06: u2 = @truncate(compressed_instruction >> 7);

    const imm: u8 =
        @as(u8, imm_07_06) << 6 |
        @as(u8, imm_05_02) << 2;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

// c.sdsp | sd rs2, offset(x2) | S-Type
// 111 | uimm[5:3] | uimm[8:6] | rs2 | 10
inline fn decompress_sdsp(compressed_instruction: u16) u32 {
    const quadrant: u2 = @truncate(compressed_instruction);
    const funct3: u3 = @truncate(compressed_instruction >> 13);

    const dispatch_key = create_dispatch_key(funct3, quadrant);
    assert(dispatch_key == .sdsp);

    const rs2: u5 = @truncate(compressed_instruction >> 2);

    var instruction: Instruction.SFields = .{
        .opcode = 0x23,
        .imm_04_00 = 0x0,
        .funct3 = 0x3,
        .rs1 = 0x2,
        .rs2 = rs2,
        .imm_11_05 = 0x0,
    };

    const imm_05_03: u3 = @truncate(compressed_instruction >> 10);
    const imm_08_06: u3 = @truncate(compressed_instruction >> 7);

    const imm: u9 =
        @as(u9, imm_08_06) << 6 |
        @as(u9, imm_05_03) << 3;

    instruction.set_imm(imm);
    return @bitCast(instruction);
}

const expectEqual = std.testing.expectEqual;

const DecompressionCase = struct {
    compressed: u16,
    full: u32,

    pub fn expect_equal(self: @This()) !void {
        try expectEqual(self.full, decompress(self.compressed));
    }
};

test "Decompress: generated boundary-value examples" {
    const cases = [_]DecompressionCase{
        // c.add: 11
        .{ .compressed = 0x9006, .full = 0x00100033 }, // add zero, zero, ra
        .{ .compressed = 0x900A, .full = 0x00200033 }, // add zero, zero, sp
        .{ .compressed = 0x903E, .full = 0x00F00033 }, // add zero, zero, a5
        .{ .compressed = 0x9042, .full = 0x01000033 }, // add zero, zero, a6
        .{ .compressed = 0x907A, .full = 0x01E00033 }, // add zero, zero, t5
        .{ .compressed = 0x907E, .full = 0x01F00033 }, // add zero, zero, t6
        .{ .compressed = 0x9086, .full = 0x001080B3 }, // add ra, ra, ra
        .{ .compressed = 0x9786, .full = 0x001787B3 }, // add a5, a5, ra
        .{ .compressed = 0x9806, .full = 0x00180833 }, // add a6, a6, ra
        .{ .compressed = 0x9F06, .full = 0x001F0F33 }, // add t5, t5, ra
        .{ .compressed = 0x9F86, .full = 0x001F8FB3 }, // add t6, t6, ra
        // c.addi: 12
        .{ .compressed = 0x0001, .full = 0x00000013 }, // addi zero, zero, 0
        .{ .compressed = 0x0005, .full = 0x00100013 }, // addi zero, zero, 1
        .{ .compressed = 0x003D, .full = 0x00F00013 }, // addi zero, zero, 15
        .{ .compressed = 0x0041, .full = 0x01000013 }, // addi zero, zero, 16
        .{ .compressed = 0x0079, .full = 0x01E00013 }, // addi zero, zero, 30
        .{ .compressed = 0x007D, .full = 0x01F00013 }, // addi zero, zero, 31
        .{ .compressed = 0x0081, .full = 0x00008093 }, // addi ra, ra, 0
        .{ .compressed = 0x0781, .full = 0x00078793 }, // addi a5, a5, 0
        .{ .compressed = 0x0F81, .full = 0x000F8F93 }, // addi t6, t6, 0
        .{ .compressed = 0x1001, .full = 0xFE000013 }, // addi zero, zero, -32
        .{ .compressed = 0x1005, .full = 0xFE100013 }, // addi zero, zero, -31
        .{ .compressed = 0x107D, .full = 0xFFF00013 }, // addi zero, zero, -1
        // c.addi16sp: 7
        .{ .compressed = 0x6105, .full = 0x02010113 }, // addi sp, sp, 32
        .{ .compressed = 0x6111, .full = 0x10010113 }, // addi sp, sp, 256
        .{ .compressed = 0x6141, .full = 0x01010113 }, // addi sp, sp, 16
        .{ .compressed = 0x616D, .full = 0x0F010113 }, // addi sp, sp, 240
        .{ .compressed = 0x617D, .full = 0x1F010113 }, // addi sp, sp, 496
        .{ .compressed = 0x7101, .full = 0xE0010113 }, // addi sp, sp, -512
        .{ .compressed = 0x717D, .full = 0xFF010113 }, // addi sp, sp, -16
        // c.addi4spn: 9
        .{ .compressed = 0x0020, .full = 0x00810413 }, // addi s0, sp, 8
        .{ .compressed = 0x0024, .full = 0x00810493 }, // addi s1, sp, 8
        .{ .compressed = 0x002C, .full = 0x00810593 }, // addi a1, sp, 8
        .{ .compressed = 0x0038, .full = 0x00810713 }, // addi a4, sp, 8
        .{ .compressed = 0x003C, .full = 0x00810793 }, // addi a5, sp, 8
        .{ .compressed = 0x0040, .full = 0x00410413 }, // addi s0, sp, 4
        .{ .compressed = 0x0400, .full = 0x20010413 }, // addi s0, sp, 512
        .{ .compressed = 0x1BE0, .full = 0x1FC10413 }, // addi s0, sp, 508
        .{ .compressed = 0x1FE0, .full = 0x3FC10413 }, // addi s0, sp, 1020
        // c.addiw: 12
        .{ .compressed = 0x2081, .full = 0x0000809B }, // addiw ra, ra, 0
        .{ .compressed = 0x2085, .full = 0x0010809B }, // addiw ra, ra, 1
        .{ .compressed = 0x20BD, .full = 0x00F0809B }, // addiw ra, ra, 15
        .{ .compressed = 0x20C1, .full = 0x0100809B }, // addiw ra, ra, 16
        .{ .compressed = 0x20F9, .full = 0x01E0809B }, // addiw ra, ra, 30
        .{ .compressed = 0x20FD, .full = 0x01F0809B }, // addiw ra, ra, 31
        .{ .compressed = 0x2781, .full = 0x0007879B }, // addiw a5, a5, 0
        .{ .compressed = 0x2801, .full = 0x0008081B }, // addiw a6, a6, 0
        .{ .compressed = 0x2F81, .full = 0x000F8F9B }, // addiw t6, t6, 0
        .{ .compressed = 0x3081, .full = 0xFE00809B }, // addiw ra, ra, -32
        .{ .compressed = 0x3085, .full = 0xFE10809B }, // addiw ra, ra, -31
        .{ .compressed = 0x30FD, .full = 0xFFF0809B }, // addiw ra, ra, -1
        // c.addw: 9
        .{ .compressed = 0x9C21, .full = 0x0084043B }, // addw s0, s0, s0
        .{ .compressed = 0x9C25, .full = 0x0094043B }, // addw s0, s0, s1
        .{ .compressed = 0x9C2D, .full = 0x00B4043B }, // addw s0, s0, a1
        .{ .compressed = 0x9C39, .full = 0x00E4043B }, // addw s0, s0, a4
        .{ .compressed = 0x9C3D, .full = 0x00F4043B }, // addw s0, s0, a5
        .{ .compressed = 0x9CA1, .full = 0x008484BB }, // addw s1, s1, s0
        .{ .compressed = 0x9DA1, .full = 0x008585BB }, // addw a1, a1, s0
        .{ .compressed = 0x9F21, .full = 0x0087073B }, // addw a4, a4, s0
        .{ .compressed = 0x9FA1, .full = 0x008787BB }, // addw a5, a5, s0
        // c.and: 9
        .{ .compressed = 0x8C61, .full = 0x00847433 }, // and s0, s0, s0
        .{ .compressed = 0x8C65, .full = 0x00947433 }, // and s0, s0, s1
        .{ .compressed = 0x8C6D, .full = 0x00B47433 }, // and s0, s0, a1
        .{ .compressed = 0x8C79, .full = 0x00E47433 }, // and s0, s0, a4
        .{ .compressed = 0x8C7D, .full = 0x00F47433 }, // and s0, s0, a5
        .{ .compressed = 0x8CE1, .full = 0x0084F4B3 }, // and s1, s1, s0
        .{ .compressed = 0x8DE1, .full = 0x0085F5B3 }, // and a1, a1, s0
        .{ .compressed = 0x8F61, .full = 0x00877733 }, // and a4, a4, s0
        .{ .compressed = 0x8FE1, .full = 0x0087F7B3 }, // and a5, a5, s0
        // c.andi: 12
        .{ .compressed = 0x8801, .full = 0x00047413 }, // andi s0, s0, 0
        .{ .compressed = 0x8805, .full = 0x00147413 }, // andi s0, s0, 1
        .{ .compressed = 0x883D, .full = 0x00F47413 }, // andi s0, s0, 15
        .{ .compressed = 0x8841, .full = 0x01047413 }, // andi s0, s0, 16
        .{ .compressed = 0x8879, .full = 0x01E47413 }, // andi s0, s0, 30
        .{ .compressed = 0x887D, .full = 0x01F47413 }, // andi s0, s0, 31
        .{ .compressed = 0x8881, .full = 0x0004F493 }, // andi s1, s1, 0
        .{ .compressed = 0x8981, .full = 0x0005F593 }, // andi a1, a1, 0
        .{ .compressed = 0x8B81, .full = 0x0007F793 }, // andi a5, a5, 0
        .{ .compressed = 0x9801, .full = 0xFE047413 }, // andi s0, s0, -32
        .{ .compressed = 0x9805, .full = 0xFE147413 }, // andi s0, s0, -31
        .{ .compressed = 0x987D, .full = 0xFFF47413 }, // andi s0, s0, -1
        // c.beqz: 11
        .{ .compressed = 0xC001, .full = 0x00040063 }, // beq s0, zero, +0
        .{ .compressed = 0xC041, .full = 0x08040063 }, // beq s0, zero, +128
        .{ .compressed = 0xC081, .full = 0x00048063 }, // beq s1, zero, +0
        .{ .compressed = 0xC181, .full = 0x00058063 }, // beq a1, zero, +0
        .{ .compressed = 0xC301, .full = 0x00070063 }, // beq a4, zero, +0
        .{ .compressed = 0xC381, .full = 0x00078063 }, // beq a5, zero, +0
        .{ .compressed = 0xCC3D, .full = 0x06040F63 }, // beq s0, zero, +126
        .{ .compressed = 0xCC75, .full = 0x0E040E63 }, // beq s0, zero, +252
        .{ .compressed = 0xCC7D, .full = 0x0E040F63 }, // beq s0, zero, +254
        .{ .compressed = 0xD001, .full = 0xF00400E3 }, // beq s0, zero, -256
        .{ .compressed = 0xDC7D, .full = 0xFE040FE3 }, // beq s0, zero, -2
        // c.bnez: 11
        .{ .compressed = 0xE001, .full = 0x00041063 }, // bne s0, zero, +0
        .{ .compressed = 0xE041, .full = 0x08041063 }, // bne s0, zero, +128
        .{ .compressed = 0xE081, .full = 0x00049063 }, // bne s1, zero, +0
        .{ .compressed = 0xE181, .full = 0x00059063 }, // bne a1, zero, +0
        .{ .compressed = 0xE301, .full = 0x00071063 }, // bne a4, zero, +0
        .{ .compressed = 0xE381, .full = 0x00079063 }, // bne a5, zero, +0
        .{ .compressed = 0xEC3D, .full = 0x06041F63 }, // bne s0, zero, +126
        .{ .compressed = 0xEC75, .full = 0x0E041E63 }, // bne s0, zero, +252
        .{ .compressed = 0xEC7D, .full = 0x0E041F63 }, // bne s0, zero, +254
        .{ .compressed = 0xF001, .full = 0xF00410E3 }, // bne s0, zero, -256
        .{ .compressed = 0xFC7D, .full = 0xFE041FE3 }, // bne s0, zero, -2
        // c.ebreak: 1
        .{ .compressed = 0x9002, .full = 0x00100073 }, // ebreak
        // c.fld: 12
        .{ .compressed = 0x2000, .full = 0x00043407 }, // fld fs0, 0(s0)
        .{ .compressed = 0x2004, .full = 0x00043487 }, // fld fs1, 0(s0)
        .{ .compressed = 0x200C, .full = 0x00043587 }, // fld fa1, 0(s0)
        .{ .compressed = 0x2018, .full = 0x00043707 }, // fld fa4, 0(s0)
        .{ .compressed = 0x201C, .full = 0x00043787 }, // fld fa5, 0(s0)
        .{ .compressed = 0x2040, .full = 0x08043407 }, // fld fs0, 128(s0)
        .{ .compressed = 0x2080, .full = 0x0004B407 }, // fld fs0, 0(s1)
        .{ .compressed = 0x2180, .full = 0x0005B407 }, // fld fs0, 0(a1)
        .{ .compressed = 0x2300, .full = 0x00073407 }, // fld fs0, 0(a4)
        .{ .compressed = 0x2380, .full = 0x0007B407 }, // fld fs0, 0(a5)
        .{ .compressed = 0x3C20, .full = 0x07843407 }, // fld fs0, 120(s0)
        .{ .compressed = 0x3C60, .full = 0x0F843407 }, // fld fs0, 248(s0)
        // c.fldsp: 9
        .{ .compressed = 0x2002, .full = 0x00013007 }, // fld ft0, 0(sp)
        .{ .compressed = 0x2012, .full = 0x10013007 }, // fld ft0, 256(sp)
        .{ .compressed = 0x2082, .full = 0x00013087 }, // fld ft1, 0(sp)
        .{ .compressed = 0x2782, .full = 0x00013787 }, // fld fa5, 0(sp)
        .{ .compressed = 0x2802, .full = 0x00013807 }, // fld fa6, 0(sp)
        .{ .compressed = 0x2F02, .full = 0x00013F07 }, // fld ft10, 0(sp)
        .{ .compressed = 0x2F82, .full = 0x00013F87 }, // fld ft11, 0(sp)
        .{ .compressed = 0x306E, .full = 0x0F813007 }, // fld ft0, 248(sp)
        .{ .compressed = 0x307E, .full = 0x1F813007 }, // fld ft0, 504(sp)
        // c.fsd: 12
        .{ .compressed = 0xA000, .full = 0x00843027 }, // fsd fs0, 0(s0)
        .{ .compressed = 0xA004, .full = 0x00943027 }, // fsd fs1, 0(s0)
        .{ .compressed = 0xA00C, .full = 0x00B43027 }, // fsd fa1, 0(s0)
        .{ .compressed = 0xA018, .full = 0x00E43027 }, // fsd fa4, 0(s0)
        .{ .compressed = 0xA01C, .full = 0x00F43027 }, // fsd fa5, 0(s0)
        .{ .compressed = 0xA040, .full = 0x08843027 }, // fsd fs0, 128(s0)
        .{ .compressed = 0xA080, .full = 0x0084B027 }, // fsd fs0, 0(s1)
        .{ .compressed = 0xA180, .full = 0x0085B027 }, // fsd fs0, 0(a1)
        .{ .compressed = 0xA300, .full = 0x00873027 }, // fsd fs0, 0(a4)
        .{ .compressed = 0xA380, .full = 0x0087B027 }, // fsd fs0, 0(a5)
        .{ .compressed = 0xBC20, .full = 0x06843C27 }, // fsd fs0, 120(s0)
        .{ .compressed = 0xBC60, .full = 0x0E843C27 }, // fsd fs0, 248(s0)
        // c.fsdsp: 9
        .{ .compressed = 0xA002, .full = 0x00013027 }, // fsd ft0, 0(sp)
        .{ .compressed = 0xA006, .full = 0x00113027 }, // fsd ft1, 0(sp)
        .{ .compressed = 0xA03E, .full = 0x00F13027 }, // fsd fa5, 0(sp)
        .{ .compressed = 0xA042, .full = 0x01013027 }, // fsd fa6, 0(sp)
        .{ .compressed = 0xA07A, .full = 0x01E13027 }, // fsd ft10, 0(sp)
        .{ .compressed = 0xA07E, .full = 0x01F13027 }, // fsd ft11, 0(sp)
        .{ .compressed = 0xA202, .full = 0x10013027 }, // fsd ft0, 256(sp)
        .{ .compressed = 0xBD82, .full = 0x0E013C27 }, // fsd ft0, 248(sp)
        .{ .compressed = 0xBF82, .full = 0x1E013C27 }, // fsd ft0, 504(sp)
        // c.j: 7
        .{ .compressed = 0xA001, .full = 0x0000006F }, // jal zero, +0
        .{ .compressed = 0xA101, .full = 0x4000006F }, // jal zero, +1024
        .{ .compressed = 0xAEFD, .full = 0x3FE0006F }, // jal zero, +1022
        .{ .compressed = 0xAFF5, .full = 0x7FC0006F }, // jal zero, +2044
        .{ .compressed = 0xAFFD, .full = 0x7FE0006F }, // jal zero, +2046
        .{ .compressed = 0xB001, .full = 0x801FF06F }, // jal zero, -2048
        .{ .compressed = 0xBFFD, .full = 0xFFFFF06F }, // jal zero, -2
        // c.jalr: 6
        .{ .compressed = 0x9082, .full = 0x000080E7 }, // jalr ra, 0(ra)
        .{ .compressed = 0x9102, .full = 0x000100E7 }, // jalr ra, 0(sp)
        .{ .compressed = 0x9782, .full = 0x000780E7 }, // jalr ra, 0(a5)
        .{ .compressed = 0x9802, .full = 0x000800E7 }, // jalr ra, 0(a6)
        .{ .compressed = 0x9F02, .full = 0x000F00E7 }, // jalr ra, 0(t5)
        .{ .compressed = 0x9F82, .full = 0x000F80E7 }, // jalr ra, 0(t6)
        // c.jr: 6
        .{ .compressed = 0x8082, .full = 0x00008067 }, // jalr zero, 0(ra)
        .{ .compressed = 0x8102, .full = 0x00010067 }, // jalr zero, 0(sp)
        .{ .compressed = 0x8782, .full = 0x00078067 }, // jalr zero, 0(a5)
        .{ .compressed = 0x8802, .full = 0x00080067 }, // jalr zero, 0(a6)
        .{ .compressed = 0x8F02, .full = 0x000F0067 }, // jalr zero, 0(t5)
        .{ .compressed = 0x8F82, .full = 0x000F8067 }, // jalr zero, 0(t6)
        // c.ld: 12
        .{ .compressed = 0x6000, .full = 0x00043403 }, // ld s0, 0(s0)
        .{ .compressed = 0x6004, .full = 0x00043483 }, // ld s1, 0(s0)
        .{ .compressed = 0x600C, .full = 0x00043583 }, // ld a1, 0(s0)
        .{ .compressed = 0x6018, .full = 0x00043703 }, // ld a4, 0(s0)
        .{ .compressed = 0x601C, .full = 0x00043783 }, // ld a5, 0(s0)
        .{ .compressed = 0x6040, .full = 0x08043403 }, // ld s0, 128(s0)
        .{ .compressed = 0x6080, .full = 0x0004B403 }, // ld s0, 0(s1)
        .{ .compressed = 0x6180, .full = 0x0005B403 }, // ld s0, 0(a1)
        .{ .compressed = 0x6300, .full = 0x00073403 }, // ld s0, 0(a4)
        .{ .compressed = 0x6380, .full = 0x0007B403 }, // ld s0, 0(a5)
        .{ .compressed = 0x7C20, .full = 0x07843403 }, // ld s0, 120(s0)
        .{ .compressed = 0x7C60, .full = 0x0F843403 }, // ld s0, 248(s0)
        // c.ldsp: 9
        .{ .compressed = 0x6082, .full = 0x00013083 }, // ld ra, 0(sp)
        .{ .compressed = 0x6092, .full = 0x10013083 }, // ld ra, 256(sp)
        .{ .compressed = 0x6102, .full = 0x00013103 }, // ld sp, 0(sp)
        .{ .compressed = 0x6782, .full = 0x00013783 }, // ld a5, 0(sp)
        .{ .compressed = 0x6802, .full = 0x00013803 }, // ld a6, 0(sp)
        .{ .compressed = 0x6F02, .full = 0x00013F03 }, // ld t5, 0(sp)
        .{ .compressed = 0x6F82, .full = 0x00013F83 }, // ld t6, 0(sp)
        .{ .compressed = 0x70EE, .full = 0x0F813083 }, // ld ra, 248(sp)
        .{ .compressed = 0x70FE, .full = 0x1F813083 }, // ld ra, 504(sp)
        // c.li: 12
        .{ .compressed = 0x4001, .full = 0x00000013 }, // addi zero, zero, 0
        .{ .compressed = 0x4005, .full = 0x00100013 }, // addi zero, zero, 1
        .{ .compressed = 0x403D, .full = 0x00F00013 }, // addi zero, zero, 15
        .{ .compressed = 0x4041, .full = 0x01000013 }, // addi zero, zero, 16
        .{ .compressed = 0x4079, .full = 0x01E00013 }, // addi zero, zero, 30
        .{ .compressed = 0x407D, .full = 0x01F00013 }, // addi zero, zero, 31
        .{ .compressed = 0x4081, .full = 0x00000093 }, // addi ra, zero, 0
        .{ .compressed = 0x4781, .full = 0x00000793 }, // addi a5, zero, 0
        .{ .compressed = 0x4F81, .full = 0x00000F93 }, // addi t6, zero, 0
        .{ .compressed = 0x5001, .full = 0xFE000013 }, // addi zero, zero, -32
        .{ .compressed = 0x5005, .full = 0xFE100013 }, // addi zero, zero, -31
        .{ .compressed = 0x507D, .full = 0xFFF00013 }, // addi zero, zero, -1
        // c.lui: 12
        .{ .compressed = 0x6005, .full = 0x00001037 }, // lui zero, 0x1
        .{ .compressed = 0x603D, .full = 0x0000F037 }, // lui zero, 0xf
        .{ .compressed = 0x6041, .full = 0x00010037 }, // lui zero, 0x10
        .{ .compressed = 0x6079, .full = 0x0001E037 }, // lui zero, 0x1e
        .{ .compressed = 0x607D, .full = 0x0001F037 }, // lui zero, 0x1f
        .{ .compressed = 0x6085, .full = 0x000010B7 }, // lui ra, 0x1
        .{ .compressed = 0x6785, .full = 0x000017B7 }, // lui a5, 0x1
        .{ .compressed = 0x6F05, .full = 0x00001F37 }, // lui t5, 0x1
        .{ .compressed = 0x6F85, .full = 0x00001FB7 }, // lui t6, 0x1
        .{ .compressed = 0x7001, .full = 0xFFFE0037 }, // lui zero, 0xfffe0
        .{ .compressed = 0x7005, .full = 0xFFFE1037 }, // lui zero, 0xfffe1
        .{ .compressed = 0x707D, .full = 0xFFFFF037 }, // lui zero, 0xfffff
        // c.lw: 12
        .{ .compressed = 0x4000, .full = 0x00042403 }, // lw s0, 0(s0)
        .{ .compressed = 0x4004, .full = 0x00042483 }, // lw s1, 0(s0)
        .{ .compressed = 0x400C, .full = 0x00042583 }, // lw a1, 0(s0)
        .{ .compressed = 0x4018, .full = 0x00042703 }, // lw a4, 0(s0)
        .{ .compressed = 0x401C, .full = 0x00042783 }, // lw a5, 0(s0)
        .{ .compressed = 0x4020, .full = 0x04042403 }, // lw s0, 64(s0)
        .{ .compressed = 0x4080, .full = 0x0004A403 }, // lw s0, 0(s1)
        .{ .compressed = 0x4180, .full = 0x0005A403 }, // lw s0, 0(a1)
        .{ .compressed = 0x4300, .full = 0x00072403 }, // lw s0, 0(a4)
        .{ .compressed = 0x4380, .full = 0x0007A403 }, // lw s0, 0(a5)
        .{ .compressed = 0x5C40, .full = 0x03C42403 }, // lw s0, 60(s0)
        .{ .compressed = 0x5C60, .full = 0x07C42403 }, // lw s0, 124(s0)
        // c.lwsp: 9
        .{ .compressed = 0x4082, .full = 0x00012083 }, // lw ra, 0(sp)
        .{ .compressed = 0x408A, .full = 0x08012083 }, // lw ra, 128(sp)
        .{ .compressed = 0x4102, .full = 0x00012103 }, // lw sp, 0(sp)
        .{ .compressed = 0x4782, .full = 0x00012783 }, // lw a5, 0(sp)
        .{ .compressed = 0x4802, .full = 0x00012803 }, // lw a6, 0(sp)
        .{ .compressed = 0x4F02, .full = 0x00012F03 }, // lw t5, 0(sp)
        .{ .compressed = 0x4F82, .full = 0x00012F83 }, // lw t6, 0(sp)
        .{ .compressed = 0x50F6, .full = 0x07C12083 }, // lw ra, 124(sp)
        .{ .compressed = 0x50FE, .full = 0x0FC12083 }, // lw ra, 252(sp)
        // c.mv: 11
        .{ .compressed = 0x8006, .full = 0x00100033 }, // add zero, zero, ra
        .{ .compressed = 0x800A, .full = 0x00200033 }, // add zero, zero, sp
        .{ .compressed = 0x803E, .full = 0x00F00033 }, // add zero, zero, a5
        .{ .compressed = 0x8042, .full = 0x01000033 }, // add zero, zero, a6
        .{ .compressed = 0x807A, .full = 0x01E00033 }, // add zero, zero, t5
        .{ .compressed = 0x807E, .full = 0x01F00033 }, // add zero, zero, t6
        .{ .compressed = 0x8086, .full = 0x001000B3 }, // add ra, zero, ra
        .{ .compressed = 0x8786, .full = 0x001007B3 }, // add a5, zero, ra
        .{ .compressed = 0x8806, .full = 0x00100833 }, // add a6, zero, ra
        .{ .compressed = 0x8F06, .full = 0x00100F33 }, // add t5, zero, ra
        .{ .compressed = 0x8F86, .full = 0x00100FB3 }, // add t6, zero, ra
        // c.or: 9
        .{ .compressed = 0x8C41, .full = 0x00846433 }, // or s0, s0, s0
        .{ .compressed = 0x8C45, .full = 0x00946433 }, // or s0, s0, s1
        .{ .compressed = 0x8C4D, .full = 0x00B46433 }, // or s0, s0, a1
        .{ .compressed = 0x8C59, .full = 0x00E46433 }, // or s0, s0, a4
        .{ .compressed = 0x8C5D, .full = 0x00F46433 }, // or s0, s0, a5
        .{ .compressed = 0x8CC1, .full = 0x0084E4B3 }, // or s1, s1, s0
        .{ .compressed = 0x8DC1, .full = 0x0085E5B3 }, // or a1, a1, s0
        .{ .compressed = 0x8F41, .full = 0x00876733 }, // or a4, a4, s0
        .{ .compressed = 0x8FC1, .full = 0x0087E7B3 }, // or a5, a5, s0
        // c.sd: 12
        .{ .compressed = 0xE000, .full = 0x00843023 }, // sd s0, 0(s0)
        .{ .compressed = 0xE004, .full = 0x00943023 }, // sd s1, 0(s0)
        .{ .compressed = 0xE00C, .full = 0x00B43023 }, // sd a1, 0(s0)
        .{ .compressed = 0xE018, .full = 0x00E43023 }, // sd a4, 0(s0)
        .{ .compressed = 0xE01C, .full = 0x00F43023 }, // sd a5, 0(s0)
        .{ .compressed = 0xE040, .full = 0x08843023 }, // sd s0, 128(s0)
        .{ .compressed = 0xE080, .full = 0x0084B023 }, // sd s0, 0(s1)
        .{ .compressed = 0xE180, .full = 0x0085B023 }, // sd s0, 0(a1)
        .{ .compressed = 0xE300, .full = 0x00873023 }, // sd s0, 0(a4)
        .{ .compressed = 0xE380, .full = 0x0087B023 }, // sd s0, 0(a5)
        .{ .compressed = 0xFC20, .full = 0x06843C23 }, // sd s0, 120(s0)
        .{ .compressed = 0xFC60, .full = 0x0E843C23 }, // sd s0, 248(s0)
        // c.sdsp: 9
        .{ .compressed = 0xE002, .full = 0x00013023 }, // sd zero, 0(sp)
        .{ .compressed = 0xE006, .full = 0x00113023 }, // sd ra, 0(sp)
        .{ .compressed = 0xE03E, .full = 0x00F13023 }, // sd a5, 0(sp)
        .{ .compressed = 0xE042, .full = 0x01013023 }, // sd a6, 0(sp)
        .{ .compressed = 0xE07A, .full = 0x01E13023 }, // sd t5, 0(sp)
        .{ .compressed = 0xE07E, .full = 0x01F13023 }, // sd t6, 0(sp)
        .{ .compressed = 0xE202, .full = 0x10013023 }, // sd zero, 256(sp)
        .{ .compressed = 0xFD82, .full = 0x0E013C23 }, // sd zero, 248(sp)
        .{ .compressed = 0xFF82, .full = 0x1E013C23 }, // sd zero, 504(sp)
        // c.slli: 11
        .{ .compressed = 0x0006, .full = 0x00101013 }, // slli zero, zero, 0x1
        .{ .compressed = 0x000A, .full = 0x00201013 }, // slli zero, zero, 0x2
        .{ .compressed = 0x007E, .full = 0x01F01013 }, // slli zero, zero, 0x1f
        .{ .compressed = 0x0086, .full = 0x00109093 }, // slli ra, ra, 0x1
        .{ .compressed = 0x0786, .full = 0x00179793 }, // slli a5, a5, 0x1
        .{ .compressed = 0x0806, .full = 0x00181813 }, // slli a6, a6, 0x1
        .{ .compressed = 0x0F06, .full = 0x001F1F13 }, // slli t5, t5, 0x1
        .{ .compressed = 0x0F86, .full = 0x001F9F93 }, // slli t6, t6, 0x1
        .{ .compressed = 0x1002, .full = 0x02001013 }, // slli zero, zero, 0x20
        .{ .compressed = 0x107A, .full = 0x03E01013 }, // slli zero, zero, 0x3e
        .{ .compressed = 0x107E, .full = 0x03F01013 }, // slli zero, zero, 0x3f
        // c.slli64: 6
        .{ .compressed = 0x0002, .full = 0x00001013 }, // slli zero, zero, 0
        .{ .compressed = 0x0082, .full = 0x00009093 }, // slli ra, ra, 0
        .{ .compressed = 0x0782, .full = 0x00079793 }, // slli a5, a5, 0
        .{ .compressed = 0x0802, .full = 0x00081813 }, // slli a6, a6, 0
        .{ .compressed = 0x0F02, .full = 0x000F1F13 }, // slli t5, t5, 0
        .{ .compressed = 0x0F82, .full = 0x000F9F93 }, // slli t6, t6, 0
        // c.srai: 10
        .{ .compressed = 0x8405, .full = 0x40145413 }, // srai s0, s0, 0x1
        .{ .compressed = 0x8409, .full = 0x40245413 }, // srai s0, s0, 0x2
        .{ .compressed = 0x847D, .full = 0x41F45413 }, // srai s0, s0, 0x1f
        .{ .compressed = 0x8485, .full = 0x4014D493 }, // srai s1, s1, 0x1
        .{ .compressed = 0x8585, .full = 0x4015D593 }, // srai a1, a1, 0x1
        .{ .compressed = 0x8705, .full = 0x40175713 }, // srai a4, a4, 0x1
        .{ .compressed = 0x8785, .full = 0x4017D793 }, // srai a5, a5, 0x1
        .{ .compressed = 0x9401, .full = 0x42045413 }, // srai s0, s0, 0x20
        .{ .compressed = 0x9479, .full = 0x43E45413 }, // srai s0, s0, 0x3e
        .{ .compressed = 0x947D, .full = 0x43F45413 }, // srai s0, s0, 0x3f
        // c.srai64: 8
        .{ .compressed = 0x8401, .full = 0x40045413 }, // srai s0, s0, 0
        .{ .compressed = 0x8481, .full = 0x4004D493 }, // srai s1, s1, 0
        .{ .compressed = 0x8501, .full = 0x40055513 }, // srai a0, a0, 0
        .{ .compressed = 0x8581, .full = 0x4005D593 }, // srai a1, a1, 0
        .{ .compressed = 0x8601, .full = 0x40065613 }, // srai a2, a2, 0
        .{ .compressed = 0x8681, .full = 0x4006D693 }, // srai a3, a3, 0
        .{ .compressed = 0x8701, .full = 0x40075713 }, // srai a4, a4, 0
        .{ .compressed = 0x8781, .full = 0x4007D793 }, // srai a5, a5, 0
        // c.srli: 10
        .{ .compressed = 0x8005, .full = 0x00145413 }, // srli s0, s0, 0x1
        .{ .compressed = 0x8009, .full = 0x00245413 }, // srli s0, s0, 0x2
        .{ .compressed = 0x807D, .full = 0x01F45413 }, // srli s0, s0, 0x1f
        .{ .compressed = 0x8085, .full = 0x0014D493 }, // srli s1, s1, 0x1
        .{ .compressed = 0x8185, .full = 0x0015D593 }, // srli a1, a1, 0x1
        .{ .compressed = 0x8305, .full = 0x00175713 }, // srli a4, a4, 0x1
        .{ .compressed = 0x8385, .full = 0x0017D793 }, // srli a5, a5, 0x1
        .{ .compressed = 0x9001, .full = 0x02045413 }, // srli s0, s0, 0x20
        .{ .compressed = 0x9079, .full = 0x03E45413 }, // srli s0, s0, 0x3e
        .{ .compressed = 0x907D, .full = 0x03F45413 }, // srli s0, s0, 0x3f
        // c.srli64: 8
        .{ .compressed = 0x8001, .full = 0x00045413 }, // srli s0, s0, 0
        .{ .compressed = 0x8081, .full = 0x0004D493 }, // srli s1, s1, 0
        .{ .compressed = 0x8101, .full = 0x00055513 }, // srli a0, a0, 0
        .{ .compressed = 0x8181, .full = 0x0005D593 }, // srli a1, a1, 0
        .{ .compressed = 0x8201, .full = 0x00065613 }, // srli a2, a2, 0
        .{ .compressed = 0x8281, .full = 0x0006D693 }, // srli a3, a3, 0
        .{ .compressed = 0x8301, .full = 0x00075713 }, // srli a4, a4, 0
        .{ .compressed = 0x8381, .full = 0x0007D793 }, // srli a5, a5, 0
        // c.sub: 9
        .{ .compressed = 0x8C01, .full = 0x40840433 }, // sub s0, s0, s0
        .{ .compressed = 0x8C05, .full = 0x40940433 }, // sub s0, s0, s1
        .{ .compressed = 0x8C0D, .full = 0x40B40433 }, // sub s0, s0, a1
        .{ .compressed = 0x8C19, .full = 0x40E40433 }, // sub s0, s0, a4
        .{ .compressed = 0x8C1D, .full = 0x40F40433 }, // sub s0, s0, a5
        .{ .compressed = 0x8C81, .full = 0x408484B3 }, // sub s1, s1, s0
        .{ .compressed = 0x8D81, .full = 0x408585B3 }, // sub a1, a1, s0
        .{ .compressed = 0x8F01, .full = 0x40870733 }, // sub a4, a4, s0
        .{ .compressed = 0x8F81, .full = 0x408787B3 }, // sub a5, a5, s0
        // c.subw: 9
        .{ .compressed = 0x9C01, .full = 0x4084043B }, // subw s0, s0, s0
        .{ .compressed = 0x9C05, .full = 0x4094043B }, // subw s0, s0, s1
        .{ .compressed = 0x9C0D, .full = 0x40B4043B }, // subw s0, s0, a1
        .{ .compressed = 0x9C19, .full = 0x40E4043B }, // subw s0, s0, a4
        .{ .compressed = 0x9C1D, .full = 0x40F4043B }, // subw s0, s0, a5
        .{ .compressed = 0x9C81, .full = 0x408484BB }, // subw s1, s1, s0
        .{ .compressed = 0x9D81, .full = 0x408585BB }, // subw a1, a1, s0
        .{ .compressed = 0x9F01, .full = 0x4087073B }, // subw a4, a4, s0
        .{ .compressed = 0x9F81, .full = 0x408787BB }, // subw a5, a5, s0
        // c.sw: 12
        .{ .compressed = 0xC000, .full = 0x00842023 }, // sw s0, 0(s0)
        .{ .compressed = 0xC004, .full = 0x00942023 }, // sw s1, 0(s0)
        .{ .compressed = 0xC00C, .full = 0x00B42023 }, // sw a1, 0(s0)
        .{ .compressed = 0xC018, .full = 0x00E42023 }, // sw a4, 0(s0)
        .{ .compressed = 0xC01C, .full = 0x00F42023 }, // sw a5, 0(s0)
        .{ .compressed = 0xC020, .full = 0x04842023 }, // sw s0, 64(s0)
        .{ .compressed = 0xC080, .full = 0x0084A023 }, // sw s0, 0(s1)
        .{ .compressed = 0xC180, .full = 0x0085A023 }, // sw s0, 0(a1)
        .{ .compressed = 0xC300, .full = 0x00872023 }, // sw s0, 0(a4)
        .{ .compressed = 0xC380, .full = 0x0087A023 }, // sw s0, 0(a5)
        .{ .compressed = 0xDC40, .full = 0x02842E23 }, // sw s0, 60(s0)
        .{ .compressed = 0xDC60, .full = 0x06842E23 }, // sw s0, 124(s0)
        // c.swsp: 9
        .{ .compressed = 0xC002, .full = 0x00012023 }, // sw zero, 0(sp)
        .{ .compressed = 0xC006, .full = 0x00112023 }, // sw ra, 0(sp)
        .{ .compressed = 0xC03E, .full = 0x00F12023 }, // sw a5, 0(sp)
        .{ .compressed = 0xC042, .full = 0x01012023 }, // sw a6, 0(sp)
        .{ .compressed = 0xC07A, .full = 0x01E12023 }, // sw t5, 0(sp)
        .{ .compressed = 0xC07E, .full = 0x01F12023 }, // sw t6, 0(sp)
        .{ .compressed = 0xC102, .full = 0x08012023 }, // sw zero, 128(sp)
        .{ .compressed = 0xDE82, .full = 0x06012E23 }, // sw zero, 124(sp)
        .{ .compressed = 0xDF82, .full = 0x0E012E23 }, // sw zero, 252(sp)
        // c.xor: 9
        .{ .compressed = 0x8C21, .full = 0x00844433 }, // xor s0, s0, s0
        .{ .compressed = 0x8C25, .full = 0x00944433 }, // xor s0, s0, s1
        .{ .compressed = 0x8C2D, .full = 0x00B44433 }, // xor s0, s0, a1
        .{ .compressed = 0x8C39, .full = 0x00E44433 }, // xor s0, s0, a4
        .{ .compressed = 0x8C3D, .full = 0x00F44433 }, // xor s0, s0, a5
        .{ .compressed = 0x8CA1, .full = 0x0084C4B3 }, // xor s1, s1, s0
        .{ .compressed = 0x8DA1, .full = 0x0085C5B3 }, // xor a1, a1, s0
        .{ .compressed = 0x8F21, .full = 0x00874733 }, // xor a4, a4, s0
        .{ .compressed = 0x8FA1, .full = 0x0087C7B3 }, // xor a5, a5, s0
    };

    for (cases) |case| {
        try case.expect_equal();
    }
}

test "Decompress: rejects reserved/illegal encodings" {
    const reserved_cases = [_]u16{
        0x0000, // reserved (c.unimp)
        0x0004, // reserved (.insn, C0 funct3=000)
        0x0010, // reserved (.insn, C0 funct3=000)
        0x001C, // reserved (.insn, C0 funct3=000)
        0x2001, // reserved (.insn, C1 funct3=001)
        0x207D, // reserved (.insn, C1 funct3=001)
        0x307D, // reserved (.insn, C1 funct3=001)
        0x4002, // reserved (.insn, C2 funct3=010)
        0x407E, // reserved (.insn, C2 funct3=010)
        0x507E, // reserved (.insn, C2 funct3=010)
        0x6001, // reserved (.insn, C1 funct3=011)
        0x6002, // reserved (.insn, C2 funct3=011)
        0x607E, // reserved (.insn, C2 funct3=011)
        0x6101, // reserved (c.addi16sp)
        0x6781, // reserved (.insn, C1 funct3=011)
        0x6F81, // reserved (.insn, C1 funct3=011)
        0x707E, // reserved (.insn, C2 funct3=011)
        0x8000, // reserved (.insn, C0 funct3=100)
        0x8002, // reserved (.insn, C2 funct3=100)
        0x8FFC, // reserved (.insn, C0 funct3=100)
        0x9C41, // reserved (.insn, C1 funct3=100)
        0x9DFD, // reserved (.insn, C1 funct3=100)
        0x9FFC, // reserved (.insn, C0 funct3=100)
        0x9FFD, // reserved (.insn, C1 funct3=100)
    };

    for (reserved_cases) |case| {
        try expectEqual(ILLEGAL_INSTRUCTION, decompress(case));
    }
}

test "Decompress: hand-picked happy-path examples" {
    const cases = [_]DecompressionCase{
        .{ .compressed = 0x10C0, .full = 0x06410413 }, // c.addi4spn: addi s0, sp, 100
        .{ .compressed = 0x1FFC, .full = 0x3FC10793 }, // c.addi4spn: addi a5, sp, 1020 (max uimm)
        .{ .compressed = 0x2D04, .full = 0x01853487 }, // c.fld: fld fs1, 24(a0)
        .{ .compressed = 0x484C, .full = 0x01442583 }, // c.lw: lw a3, 20(s0)
        .{ .compressed = 0x6490, .full = 0x0084B603 }, // c.ld: ld a2, 8(s1)
        .{ .compressed = 0xA814, .full = 0x00D43827 }, // c.fsd: fsd fa5, 16(s0)
        .{ .compressed = 0xC54C, .full = 0x00B52623 }, // c.sw: sw a3, 12(a0)
        .{ .compressed = 0xF498, .full = 0x02E4B423 }, // c.sd: sd a4, 40(s1)
        .{ .compressed = 0x031D, .full = 0x00730313 }, // c.addi: addi t1, t1, 7
        .{ .compressed = 0x1755, .full = 0xFF570713 }, // c.addi: addi a4, a4, -11
        .{ .compressed = 0x2995, .full = 0x0059899B }, // c.addiw: addiw s3, s3, 5
        .{ .compressed = 0x5505, .full = 0xFE100513 }, // c.li: li a0, -31
        .{ .compressed = 0x4E45, .full = 0x01100E13 }, // c.li: li t3, 17
        .{ .compressed = 0x6145, .full = 0x03010113 }, // c.addi16sp: addi sp, sp, 48
        .{ .compressed = 0x7139, .full = 0xFC010113 }, // c.addi16sp: addi sp, sp, -64
        .{ .compressed = 0x6E95, .full = 0x00005EB7 }, // c.lui: lui t4, 0x5
        .{ .compressed = 0x7585, .full = 0xFFFE15B7 }, // c.lui: lui a1, 0xfffe1 (negative)
        .{ .compressed = 0x810D, .full = 0x00355513 }, // c.srli: srli a0, a0, 3
        .{ .compressed = 0x86A5, .full = 0x4096D693 }, // c.srai: srai a5, a5, 9
        .{ .compressed = 0x989D, .full = 0xFE74F493 }, // c.andi: andi s1, s1, -25
        .{ .compressed = 0x8D91, .full = 0x40C585B3 }, // c.sub: sub a3, a3, s4
        .{ .compressed = 0x8C3D, .full = 0x00F44433 }, // c.xor: xor s0, s0, a5
        .{ .compressed = 0x8F49, .full = 0x00A76733 }, // c.or: or a4, a4, a0
        .{ .compressed = 0x8CE1, .full = 0x0084F4B3 }, // c.and: and s1, s1, s0
        .{ .compressed = 0x9D15, .full = 0x40D5053B }, // c.subw: subw a0, a0, a5
        .{ .compressed = 0x9E25, .full = 0x0096063B }, // c.addw: addw s2, s2, s1
        .{ .compressed = 0xA095, .full = 0x0640006F }, // c.j: jal zero, +100
        .{ .compressed = 0xB531, .full = 0xE0DFF06F }, // c.j: jal zero, -500
        .{ .compressed = 0xC991, .full = 0x00058A63 }, // c.beqz: beqz a3, +20
        .{ .compressed = 0xD475, .full = 0xFE0406E3 }, // c.beqz: beqz s0, -20
        .{ .compressed = 0xE685, .full = 0x02069463 }, // c.bnez: bnez a5, +40
        .{ .compressed = 0x03B6, .full = 0x00D39393 }, // c.slli: slli t2, t2, 13
        .{ .compressed = 0x3606, .full = 0x06013607 }, // c.fldsp: fld f12, 96(sp)
        .{ .compressed = 0x5AA2, .full = 0x02812A83 }, // c.lwsp: lw s5, 40(sp)
        .{ .compressed = 0x62E6, .full = 0x05813283 }, // c.ldsp: ld t0, 88(sp)
        .{ .compressed = 0x8302, .full = 0x00030067 }, // c.jr: jalr zero, 0(t1)
        .{ .compressed = 0x8B32, .full = 0x00C00B33 }, // c.mv: add s6, zero, a2
        .{ .compressed = 0x9E02, .full = 0x000E00E7 }, // c.jalr: jalr ra, 0(t3)
        .{ .compressed = 0x9BB6, .full = 0x00DB8BB3 }, // c.add: add s7, s7, a3
        .{ .compressed = 0xA4A6, .full = 0x04913427 }, // c.fsdsp: fsd f9, 72(sp)
        .{ .compressed = 0xCE46, .full = 0x01112E23 }, // c.swsp: sw a7, 28(sp)
        .{ .compressed = 0xE3FA, .full = 0x1DE13023 }, // c.sdsp: sd t5, 56(sp)
        .{ .compressed = 0x9002, .full = 0x00100073 }, // c.ebreak: ebreak
    };

    for (cases) |case| {
        try case.expect_equal();
    }
}

test "Decompress: hand-picked reserved/illegal encodings" {
    const reserved_cases = [_]u16{
        0x000C, // c.addi4spn: rd'=a3 but uimm=0 -> reserved (nzuimm must be nonzero)
        0x2055, // c.addiw: rd=0 -> reserved
        0x6101, // c.addi16sp: imm=0, rd=sp -> reserved (nzimm must be nonzero)
        0x6301, // c.lui-form: imm=0, rd=t1 -> reserved (same imm==0 check applies regardless of rd)
        0x507E, // c.lwsp: rd=0 -> reserved
        0x707E, // c.ldsp: rd=0 -> reserved
        0x8002, // c.jr-form: rs1=0 (rd field), rs2=0, bit12=0 -> reserved (rd/rs1 must be nonzero)
    };

    for (reserved_cases) |case| {
        try expectEqual(ILLEGAL_INSTRUCTION, decompress(case));
    }
}

test "Decompress: hand-picked HINT encodings" {
    const hint_cases = [_]DecompressionCase{
        .{ .compressed = 0x1015, .full = 0xFE500013 }, // c.addi HINT: rd=x0, imm=-27 (nonzero, non-nop) -> addi zero, zero, -27
        .{ .compressed = 0x5029, .full = 0xFEA00013 }, // c.li HINT: rd=x0 -> addi zero, zero, -22
        .{ .compressed = 0x6015, .full = 0x00005037 }, // c.lui HINT: rd=x0, nonzero imm -> lui zero, 0x5
        .{ .compressed = 0x8036, .full = 0x00D00033 }, // c.mv HINT: rd=x0, rs2=a3 -> add zero, zero, a3
        .{ .compressed = 0x9036, .full = 0x00D00033 }, // c.add HINT: rd=x0, rs2=a3 -> add zero, zero, a3
        .{ .compressed = 0x002A, .full = 0x00A01013 }, // c.slli HINT: rd=x0, shamt=10 -> slli zero, zero, 0xa
    };

    for (hint_cases) |case| {
        try case.expect_equal();
    }
}
