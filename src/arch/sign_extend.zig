const std = @import("std");

// Widens any signed or unsigned integer (2-64 bits) to i64 by sign extension
pub inline fn sign_extend(source: anytype) i64 {
    const info = @typeInfo(@TypeOf(source));
    comptime validate_type(info);

    const SignedType = @Int(.signed, info.int.bits);
    const signed_source: SignedType = @bitCast(source);

    const sign_extended_source: i64 = signed_source;
    return sign_extended_source;
}

fn validate_type(comptime info: std.builtin.Type) void {
    if (info != .int) {
        @compileError("expected an integer type");
    }

    if (info.int.bits > 64 or info.int.bits < 2) {
        @compileError("expected integers of width from 2 to 64 bits");
    }
}

const expectEqual = std.testing.expectEqual;

test "sign_extend: zero, max positive, and mid for every width" {
    const ZERO_I64: i64 = 0;

    inline for (2..65) |index| {
        const bits: u8 = @truncate(index);

        const SourceType = @Int(.unsigned, bits);

        const ZERO: SourceType = 0;
        try expectEqual(ZERO_I64, sign_extend(ZERO));

        const MAX: SourceType = std.math.maxInt(SourceType);

        const NEGATIVE_ONE_I64: i64 = -1;
        try expectEqual(NEGATIVE_ONE_I64, sign_extend(MAX));

        const MID: SourceType = MAX >> 1;
        const MID_I64: i64 = @intCast(MID);

        try expectEqual(MID_I64, sign_extend(MID));
    }
}

test "sign_extend: 1, -1 and -2 for every width" {
    inline for (2..65) |index| {
        const bits: u8 = @truncate(index);

        const SourceType = @Int(.unsigned, bits);
        const SignedSourceType = @Int(.signed, bits);

        const ONE: SourceType = 1;
        const NEGATIVE_ONE: SignedSourceType = -1;
        const NEGATIVE_TWO: SignedSourceType = -2;

        const ONE_I64: i64 = 1;
        const NEGATIVE_ONE_I64: i64 = -1;
        const NEGATIVE_TWO_I64: i64 = -2;

        try expectEqual(ONE_I64, sign_extend(ONE));
        try expectEqual(NEGATIVE_ONE_I64, sign_extend(NEGATIVE_ONE));
        try expectEqual(NEGATIVE_TWO_I64, sign_extend(NEGATIVE_TWO));
    }
}

test "sign_extend: sign-bit boundary" {
    inline for (2..65) |index| {
        const bits: u8 = @truncate(index);

        const SourceType = @Int(.unsigned, bits);
        const SignedSourceType = @Int(.signed, bits);

        const MIN_SIGNED: SignedSourceType = std.math.minInt(SignedSourceType);
        const MIN_SIGNED_I64 = MIN_SIGNED;

        const boundary_value: SourceType = 1 << (bits - 1);
        try expectEqual(MIN_SIGNED_I64, sign_extend(boundary_value));
    }
}

test "sign_extend: randomized sign extensions" {
    var prng = std.Random.DefaultPrng.init(0xBADF00D);
    const random = prng.random();

    inline for (2..65) |index| {
        const bits: u8 = @truncate(index);

        const SourceType = @Int(.unsigned, bits);
        const SignedSourceType = @Int(.signed, bits);

        for (0..10000) |_| {
            const value: SourceType = random.int(SourceType);
            const value_signed: SignedSourceType = @bitCast(value);
            try expectEqual(@as(i64, value_signed), sign_extend(value));

            const signed = random.int(SignedSourceType);
            try expectEqual(@as(i64, signed), sign_extend(signed));
        }
    }
}
