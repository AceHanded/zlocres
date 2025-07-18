const std = @import("std");

/// Decodes a UTF-16LE byte slice to a UTF-8 byte slice.
fn decodeUtf16LeToUtf8(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len % 2 != 0) return error.InvalidUtf16Length;

    var utf8_list = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    for (0..input.len) |byte_idx| {
        if (byte_idx % 2 != 0) continue;
        if (i != byte_idx) break;

        const lo: u8 = input[i];
        const hi: u8 = input[i + 1];
        i += 2;

        const unit: u16 = (@as(u16, hi) << 8) | lo;
        if (std.unicode.utf16IsLowSurrogate(unit)) return error.UnexpectedLowSurrogate;

        var codepoint: u21 = undefined;

        if (std.unicode.utf16IsHighSurrogate(unit)) {
            if (i + 1 >= input.len) return error.UnexpectedEndOfData;

            const lo2: u8 = input[i];
            const hi2: u8 = input[i + 1];
            i += 2;

            const next: u16 = (@as(u16, hi2) << 8) | lo2;
            if (!std.unicode.utf16IsLowSurrogate(next)) return error.InvalidSurrogatePair;

            codepoint = 0x10000 + (((@as(u21, unit - 0xD800)) << 10) | (@as(u21, next - 0xDC00)));
        } else {
            codepoint = unit;
        }
        var buf: [4]u8 = undefined;
        const encoded_len: u3 = try std.unicode.utf8Encode(codepoint, &buf);
        try utf8_list.writer().writeAll(buf[0..encoded_len]);
    }
    return utf8_list.toOwnedSlice();
}

/// Returns whether the string consists of 7-bit ASCII characters.
fn asciiStr(s: []const u8) bool {
    for (s) |ch| {
        if (!std.ascii.isAscii(ch)) return false;
    }
    return true;
}

/// Custom type for reading data from a file.
pub const Reader = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,

    /// Initializes a `Reader` instance.
    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) Reader {
        return Reader{ .allocator = allocator, .file = file };
    }

    /// Deinitializes the `Reader` instance by closing the file.
    pub fn deinit(self: *Reader) void {
        self.file.close();
    }

    /// Returns the current position of the file pointer.
    pub fn getPos(self: *const Reader) !u64 {
        return self.file.getPos();
    }

    /// Sets the current position of the file pointer.
    pub fn setPos(self: *Reader, position: u64) !void {
        try self.file.seekTo(position);
    }

    /// Reads the given amount of bytes from the file.
    pub fn read(self: *Reader, size: usize) ![]const u8 {
        const read_buf: []u8 = try self.allocator.alloc(u8, size);
        const read_bytes: usize = try self.file.readAll(read_buf);
        return read_buf[0..read_bytes];
    }

    /// Reads a `u8` type from the file.
    pub fn uint(self: *Reader) !u8 {
        var buf: [1]u8 = undefined;
        _ = try self.file.readAll(&buf);
        return buf[0];
    }

    /// Reads a `u32` type from the file.
    pub fn uint32(self: *Reader) !u32 {
        var buf: [4]u8 = undefined;
        _ = try self.file.readAll(&buf);
        return std.mem.readInt(u32, &buf, .little);
    }

    /// Reads a `u64` type from the file.
    pub fn uint64(self: *Reader) !u64 {
        var buf: [8]u8 = undefined;
        _ = try self.file.readAll(&buf);
        return std.mem.readInt(u64, &buf, .little);
    }

    /// Reads a `i32` type from the file.
    pub fn int32(self: *Reader) !i32 {
        var buf: [4]u8 = undefined;
        _ = try self.file.readAll(&buf);
        return std.mem.readInt(i32, &buf, .little);
    }

    /// Reads a UTF-8 or UTF-16LE string from the file and returns it as a UTF-8 slice.
    pub fn string(self: *Reader) ![]const u8 {
        const length: i32 = try self.int32();
        if (length == 0) return "";

        // UTF-8 encoded strings have a positive length
        if (length > 0) {
            const raw: []const u8 = try self.read(@intCast(length));
            return std.mem.trimRight(u8, raw, "\x00");
        }
        const raw: []const u8 = try self.read(@as(u32, @intCast(-@as(i32, length))) * 2);
        const decoded: []u8 = try decodeUtf16LeToUtf8(self.allocator, raw);
        return std.mem.trimRight(u8, decoded, "\x00");
    }

    /// Reads a list of UTF-8 or UTF-16LE strings from the file as UTF-8 slices.
    pub fn string_list(self: *Reader) ![][]const u8 {
        const length: u32 = try self.uint32();
        var list = try std.ArrayList([]const u8).initCapacity(self.allocator, length);

        for (0..length) |_| {
            try list.append(try self.string());
        }
        return list.toOwnedSlice();
    }
};

/// Custom type for writing data to a file.
pub const Writer = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,

    /// Initializes a `Writer` instance.
    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) Writer {
        return Writer{ .allocator = allocator, .file = file };
    }

    /// Deinitializes the `Writer` instance by closing the file.
    pub fn deinit(self: *Writer) void {
        self.file.close();
    }

    /// Returns the current position of the file pointer.
    pub fn getPos(self: *const Writer) !u64 {
        return self.file.getPos();
    }

    /// Sets the current position of the file pointer.
    pub fn setPos(self: *Writer, position: usize) !void {
        try self.file.seekTo(position);
    }

    /// Writes the given data to the file.
    pub fn write(self: *Writer, data: []const u8) !void {
        try self.file.writeAll(data);
    }

    /// Writes a `u8` type to the file.
    pub fn uint(self: *Writer, val: u8) !void {
        try self.write(&[_]u8{val});
    }

    /// Writes a `u32` type to the file.
    pub fn uint32(self: *Writer, val: u32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, val, .little);
        try self.write(&buf);
    }

    /// Writes a `u64` type to the file.
    pub fn uint64(self: *Writer, val: u64) !void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, val, .little);
        try self.write(&buf);
    }

    /// Writes a `i32` type to the file.
    pub fn int32(self: *Writer, val: i32) !void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(i32, &buf, val, .little);
        try self.write(&buf);
    }

    /// Writes a UTF-8 or UTF-16LE string to the file with the length prefix and null terminator.
    pub fn string(self: *Writer, val: []const u8, unicode: bool) !void {
        const value: []const u8 = val;
        const null_terminated: []u8 = try std.mem.concat(self.allocator, u8, &[_][]const u8{value, "\x00"});
        defer self.allocator.free(null_terminated);

        if (!unicode and asciiStr(null_terminated)) {
            try self.uint32(@as(u32, @intCast(null_terminated.len)));
            try self.write(null_terminated);
            return;
        }
        const utf16le: []u16 = try std.unicode.utf8ToUtf16LeAlloc(self.allocator, null_terminated);
        defer self.allocator.free(utf16le);

        try self.int32(-@as(i32, @intCast(utf16le.len)));
        try self.write(std.mem.sliceAsBytes(utf16le));
    }

    /// Writes a list of UTF-8 strings to the file with length prefixes and null terminators.
    pub fn string_list(self: *Writer, items: []const []const u8) !void {
        try self.uint32(@as(u32, @intCast(items.len)));

        for (items) |item| {
            try self.string(item, false);
        }
    }
};
