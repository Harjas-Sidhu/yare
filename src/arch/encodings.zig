pub const Opcode = enum(u5) {
    load = 0x0,
    load_fp = 0x1,
    misc_mem = 0x3,
    op_imm = 0x4,
    auipc = 0x5,
    op_imm_32 = 0x6,
    store = 0x8,
    store_fp = 0x9,
    amo = 0xB,
    op = 0xC,
    lui = 0xD,
    op_32 = 0xE,
    madd = 0x10,
    msub = 0x11,
    nmsub = 0x12,
    nmadd = 0x13,
    op_fp = 0x14,
    op_v = 0x15,
    branch = 0x18,
    jalr = 0x19,
    jal = 0x1B,
    system = 0x1C,
    op_ve = 0x1D,

    // un-mapped values
    _,

    pub fn raw(opcode: Opcode) u7 {
        const raw_opcode: u7 = @intFromEnum(opcode);
        return raw_opcode << 2 | 0x3;
    }
};
