const std = @import("std");

const assert = std.debug.assert;
const MAX = std.math.maxInt(u64);

base: u64,
size: u64,

/// A non-empty half-open address range [base, base + size).
/// `size` must be greater than zero, and `base + size` must not overflow `u64`.
const Self = @This();

fn assert_valid(base: u64, size: u64) void {
    assert(size > 0);
    assert(base <= MAX - size); // Overflow guard
}

/// Represents an arbitrary address region.
pub fn init(base: u64, size: u64) Self {
    assert_valid(base, size);
    return .{ .base = base, .size = size };
}

pub inline fn end(region: Self) u64 {
    assert_valid(region.base, region.size);
    return region.base + region.size;
}

pub inline fn contains(region: Self, address: u64) bool {
    assert_valid(region.base, region.size);
    return region.base <= address and address < region.end();
}

pub inline fn contains_region(region: Self, other: Self) bool {
    assert_valid(region.base, region.size);
    assert_valid(other.base, other.size);

    const starts_inside = region.base <= other.base;
    const ends_inside = other.end() <= region.end();

    return starts_inside and ends_inside;
}

pub inline fn offset(region: Self, address: u64) u64 {
    assert_valid(region.base, region.size);
    assert(region.contains(address));

    return address - region.base;
}

pub inline fn overlaps(region: Self, other: Self) bool {
    assert_valid(region.base, region.size);
    assert_valid(other.base, other.size);

    return region.base < other.end() and other.base < region.end();
}

const expectEqual = std.testing.expectEqual;

test "Region: init" {
    const region: Self = .init(0x100, 10);
    const region_overlapping: Self = .init(0x105, 3);
    const region_non_overlapping: Self = .init(0x10A, 1);

    try expectEqual(0x10A, region.end());

    try expectEqual(true, region.contains(0x105));
    try expectEqual(true, region.contains(0x100));
    try expectEqual(false, region.contains(0x10A));

    try expectEqual(true, region.contains_region(region_overlapping));

    try expectEqual(3, region.offset(0x103));
    try expectEqual(8, region.offset(0x108));
    try expectEqual(9, region.offset(0x109));

    try expectEqual(true, region.overlaps(region_overlapping));
    try expectEqual(false, region.overlaps(region_non_overlapping));
}

test "Region: single address" {
    const region: Self = .init(0x100, 1);

    try expectEqual(0x101, region.end());

    try expectEqual(true, region.contains(0x100));
    try expectEqual(false, region.contains(0x101));

    try expectEqual(0, region.offset(0x100));
}

test "Region: maximum valid end" {
    const region: Self = .init(MAX - 1, 1);

    try expectEqual(MAX, region.end());
    try expectEqual(true, region.contains(MAX - 1));
    try expectEqual(false, region.contains(MAX));
}

test "Region: maximum size" {
    const region: Self = .init(0, MAX);

    try expectEqual(MAX, region.end());

    try expectEqual(true, region.contains(0));
    try expectEqual(true, region.contains(MAX - 1));
    try expectEqual(false, region.contains(MAX));

    try expectEqual(0, region.offset(0));
    try expectEqual(MAX - 1, region.offset(MAX - 1));
}

test "Region: contains" {
    const region: Self = .init(0x100, 10);

    try expectEqual(true, region.contains(0x100));
    try expectEqual(true, region.contains(0x105));
    try expectEqual(true, region.contains(0x109));

    try expectEqual(false, region.contains(0x0FF));
    try expectEqual(false, region.contains(0x10A));
}

test "Region: offset" {
    const region: Self = .init(0x100, 10);

    try expectEqual(0, region.offset(0x100));
    try expectEqual(3, region.offset(0x103));
    try expectEqual(8, region.offset(0x108));
    try expectEqual(9, region.offset(0x109));
}

test "Region: contains_region" {
    const region: Self = .init(0x100, 10);

    const contained: Self = .init(0x103, 3);
    const exact: Self = .init(0x100, 10);
    const containing: Self = .init(0x0F0, 0x30);
    const partial_left: Self = .init(0x0F5, 0x10);
    const partial_right: Self = .init(0x105, 0x10);
    const before: Self = .init(0x080, 10);
    const after: Self = .init(0x10A, 10);

    try expectEqual(true, region.contains_region(contained));
    try expectEqual(true, region.contains_region(exact));

    try expectEqual(false, region.contains_region(containing));
    try expectEqual(false, region.contains_region(partial_left));
    try expectEqual(false, region.contains_region(partial_right));
    try expectEqual(false, region.contains_region(before));
    try expectEqual(false, region.contains_region(after));
}

test "Region: randomized invariants" {
    var prng = std.Random.DefaultPrng.init(0xBADC0FFE);
    const random = prng.random();

    for (0..100000) |_| {
        const base = random.int(u64);
        const max_size = MAX - base;

        if (max_size == 0) continue;

        const size = random.intRangeAtMost(u64, 1, max_size);
        const region: Self = .init(base, size);

        const region_end = base + size;

        try expectEqual(base, region.base);
        try expectEqual(size, region.size);
        try expectEqual(region_end, region.end());

        try expectEqual(true, region.contains(base));
        try expectEqual(false, region.contains(region_end));

        try expectEqual(0, region.offset(base));
        try expectEqual(size - 1, region.offset(region_end - 1));

        const address = random.intRangeAtMost(u64, base, region_end - 1);
        const region_offset = region.offset(address);

        try expectEqual(true, region_offset < region.size);
        try expectEqual(address, region.base + region_offset);
    }
}

test "Region: randomized relationships" {
    var prng = std.Random.DefaultPrng.init(0xF1FAF00D);
    const random = prng.random();

    for (0..100000) |_| {
        const base_a = random.int(u64);
        const base_b = random.int(u64);

        const max_size_a = MAX - base_a;
        const max_size_b = MAX - base_b;

        if (max_size_a == 0 or max_size_b == 0) continue;

        const size_a = random.intRangeAtMost(u64, 1, max_size_a);
        const size_b = random.intRangeAtMost(u64, 1, max_size_b);

        const a: Self = .init(base_a, size_a);
        const b: Self = .init(base_b, size_b);

        const end_a = base_a + size_a;
        const end_b = base_b + size_b;

        const expected_overlap =
            !(end_a <= base_b or end_b <= base_a);

        try expectEqual(expected_overlap, a.overlaps(b));
        try expectEqual(expected_overlap, b.overlaps(a));

        const expected_a_contains_b =
            base_a <= base_b and end_b <= end_a;

        try expectEqual(expected_a_contains_b, a.contains_region(b));

        const expected_b_contains_a =
            base_b <= base_a and end_a <= end_b;

        try expectEqual(expected_b_contains_a, b.contains_region(a));
    }
}

test "Region: overlaps" {
    const region: Self = .init(0x100, 10);

    const exact: Self = .init(0x100, 10);
    const contained: Self = .init(0x103, 3);
    const containing: Self = .init(0x0F0, 0x30);
    const partial_left: Self = .init(0x0F5, 0x10);
    const partial_right: Self = .init(0x105, 0x10);
    const before: Self = .init(0x080, 10);
    const after: Self = .init(0x10A, 10);

    try expectEqual(true, region.overlaps(exact));
    try expectEqual(true, region.overlaps(contained));
    try expectEqual(true, region.overlaps(containing));
    try expectEqual(true, region.overlaps(partial_left));
    try expectEqual(true, region.overlaps(partial_right));

    try expectEqual(false, region.overlaps(before));
    try expectEqual(false, region.overlaps(after));
}

test "Region: adjacent regions do not overlap" {
    const region: Self = .init(0x100, 10);
    const adjacent: Self = .init(0x10A, 10);

    try expectEqual(false, region.overlaps(adjacent));
    try expectEqual(false, adjacent.overlaps(region));

    try expectEqual(false, region.contains_region(adjacent));
    try expectEqual(false, adjacent.contains_region(region));
}
