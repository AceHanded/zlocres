const hash = @import("hash.zig");
const std = @import("std");
const testing = std.testing;

test "CityHash" {
    const allocator = std.heap.page_allocator;
    try testing.expect(try hash.hashUtf16ToU32(allocator, "example") == 0xbf7a4ae6);
}

test "CRCHash" {
    try testing.expect(hash.crcHash32("example") == 0x7c20ea98);
}
