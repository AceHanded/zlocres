const std = @import("std");
const hash = @import("hash.zig");
const file_io = @import("file_io.zig");
const Reader = file_io.Reader;
const Writer = file_io.Writer;

const LOCMETA_MAGIC: []const u8 = &[16]u8{ 0x4F, 0xEE, 0x4C, 0xA1, 0x68, 0x48, 0x55, 0x83, 0x6C, 0x4C, 0x46, 0xBD, 0x70, 0xDA, 0x50, 0x7C };
const LOCRES_MAGIC: []const u8 = &[16]u8{ 0x0E, 0x14, 0x74, 0x75, 0x67, 0x4A, 0x03, 0xFC, 0x4A, 0x15, 0x90, 0x9D, 0xC3, 0x37, 0x7F, 0x1B };

pub const LocmetaVer = enum(u1) { V0, V1 };
pub const LocresVer = enum(u2) { Legacy, Compact, Optimized, CityHash };

/// Custom type for `locmeta` data.
pub const Locmeta = struct {
    version: LocmetaVer,
    native_culture: []const u8,
    native_locres: []const u8,
    compiled_cultures: []const []const u8,

    /// Initializes a `Locmeta` instance.
    pub fn init(version: LocmetaVer, native_culture: []const u8, native_locres: []const u8, compiled_cultures: []const []const u8) Locmeta {
        return Locmeta{ .version = version, .native_culture = native_culture, .native_locres = native_locres, .compiled_cultures = compiled_cultures };
    }
};

/// Custom type for reading and writing `locmeta` files.
pub const LocmetaFile = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    /// Initializes a `LocmetaFile` instance. \
    /// Returns an error if the extension is not `.locmeta`.
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !LocmetaFile {
        if (!std.mem.endsWith(u8, path, ".locmeta")) return error.InvalidFileExtension;
        return LocmetaFile{ .allocator = allocator, .path = path };
    }

    /// Reads the contents of the `locmeta` file.
    pub fn read(self: *LocmetaFile) !Locmeta {
        const file = try std.fs.cwd().openFile(self.path, .{ .mode = .read_only });
        var reader: Reader = Reader.init(self.allocator, file);
        defer reader.deinit();

        try reader.setPos(0);  // Ensure the reading begins from the start of the file
        const magic: []const u8 = try reader.read(16);
        if (!std.mem.eql(u8, magic, LOCMETA_MAGIC)) return error.InvalidFormat;

        const version_num: u8 = try reader.uint();
        const version: LocmetaVer = @enumFromInt(version_num);
        if (version_num > @intFromEnum(LocmetaVer.V1)) return error.InvalidVersion;

        const native_culture: []const u8 = try reader.string();
        const native_locres: []const u8 = try reader.string();
        const compiled_cultures: [][]const u8 = if (version_num == @intFromEnum(LocmetaVer.V1)) try reader.string_list() else &[0][]const u8{};

        return Locmeta.init(version, native_culture, native_locres, compiled_cultures);
    }

    /// Writes the data to the `locmeta` file.
    pub fn write(self: *LocmetaFile, locmeta: Locmeta) !void {
        // If the file already exists at the given path, overwrite it, otherwise create a new one
        const file = std.fs.cwd().openFile(self.path, .{ .mode = .read_write }) catch
            try std.fs.cwd().createFile(self.path, .{ .read = true });

        try file.setEndPos(0);  // Truncate the file
        var writer: Writer = Writer.init(self.allocator, file);
        defer writer.deinit();

        const version_num: u1 = @intFromEnum(locmeta.version);
        try writer.write(LOCMETA_MAGIC);
        try writer.uint(version_num);
        try writer.string(locmeta.native_culture, false);
        try writer.string(locmeta.native_locres, false);
        if (version_num == @intFromEnum(LocmetaVer.V1)) try writer.string_list(locmeta.compiled_cultures);
    }
};

/// Custom type for `locres` data.
pub const Locres = struct {
    version: LocresVer,
    namespaces: std.StringArrayHashMap(LocresNamespace),

    /// Initializes a `Locres` instance.
    pub fn init(allocator: std.mem.Allocator, version: LocresVer) Locres {
        return Locres{ .version = version, .namespaces = std.StringArrayHashMap(LocresNamespace).init(allocator) };
    }

    /// Deinitializes the `Locres` instance by freeing the namespaces.
    pub fn deinit(self: *Locres) void {
        var ns_iter = self.namespaces.iterator();

        while (ns_iter.next()) |ns_entry| {
            ns_entry.value_ptr.deinit();
        }
        self.namespaces.deinit();
    }

    /// Returns the namespace corresponding to the given key. \
    /// Returns `null` if the key was not found.
    pub fn get(self: *const Locres, key: []const u8) ?LocresNamespace {
        return self.namespaces.get(key);
    }

    /// Sets a new namespace for the given key.
    pub fn set(self: *Locres, key: []const u8, namespace: LocresNamespace) !void {
        try self.namespaces.put(key, namespace);
    }

    /// Removes the namespace corresponding to the given key.
    pub fn remove(self: *Locres, key: []const u8) void {
        _ = self.namespaces.orderedRemove(key);
    }

    /// Returns the number of namespaces in the locres as a `u32` type.
    pub fn count(self: *const Locres) u32 {
        return @intCast(self.namespaces.count());
    }
};

/// Custom type for a `locres` entry.
pub const LocresEntry = struct {
    key: []const u8,
    translation: []const u8,
    hash_val: u32,
    string_index: ?u32 = null,

    /// Initializes a `LocresEntry` instance.
    pub fn init(key: []const u8, translation: []const u8, hash_val: u32) LocresEntry {
        return LocresEntry{ .key = key, .translation = translation, .hash_val = hash_val };
    }
};

/// Custom type for a `locres` namespace.
pub const LocresNamespace = struct {
    name: []const u8,
    entries: std.StringArrayHashMap(LocresEntry),

    /// Initializes a `LocresNamespace` instance.
    pub fn init(allocator: std.mem.Allocator, name: []const u8) LocresNamespace {
        return LocresNamespace{ .name = name, .entries = std.StringArrayHashMap(LocresEntry).init(allocator) };
    }

    /// Deinitializes the `LocresNamespace` instance by freeing the entries.
    pub fn deinit(self: *LocresNamespace) void {
        self.entries.deinit();
    }

    /// Returns the entry corresponding to the given key. \
    /// Returns `null` if the key was not found.
    pub fn get(self: *const LocresNamespace, key: []const u8) ?LocresEntry {
        return self.entries.get(key);
    }

    /// Sets a new entry for the given key.
    pub fn set(self: *LocresNamespace, key: []const u8, entry: LocresEntry) !void {
        try self.entries.put(key, entry);
    }

    /// Removes the entry corresponding to the given key.
    pub fn remove(self: *LocresNamespace, key: []const u8) void {
        _ = self.entries.orderedRemove(key);
    }

    /// Returns the number of entries in the namespace as a `u32` type.
    pub fn count(self: *const LocresNamespace) u32 {
        return @intCast(self.entries.count());
    }
};

/// Custom type for reading and writing `locres` files.
pub const LocresFile = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    /// Initializes a `LocresFile` instance. \
    /// Returns an error if the extension is not `.locres`.
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !LocresFile {
        if (!std.mem.endsWith(u8, path, ".locres")) return error.InvalidFileExtension;
        return LocresFile{ .allocator = allocator, .path = path };
    }

    /// Reads the contents of the `locres` file.
    pub fn read(self: *LocresFile) !Locres {
        const file = try std.fs.cwd().openFile(self.path, .{ .mode = .read_only });
        var reader: Reader = Reader.init(self.allocator, file);
        defer reader.deinit();

        try reader.setPos(0);
        var version: LocresVer = LocresVer.Legacy;
        var strings = std.ArrayList([]const u8).init(self.allocator);
        defer strings.deinit();

        // Read reader
        const magic: []const u8 = try reader.read(16);
        var offset: u64 = 0;

        if (std.mem.eql(u8, magic, LOCRES_MAGIC)) {
            version = @enumFromInt(try reader.uint());
            offset = try reader.uint64();
        }
        const version_num: u2 = @intFromEnum(version);
        var locres: Locres = Locres.init(self.allocator, version);

        // Read strings
        if (version_num >= @intFromEnum(LocresVer.Compact)) {
            try reader.setPos(offset);
            const string_count: u32 = try reader.uint32();

            for (0..string_count) |_| {
                const string: []const u8 = try reader.string();
                if (version_num >= @intFromEnum(LocresVer.Optimized)) _ = try reader.uint32();
                
                try strings.append(string);
            }
        }
        // Read keys
        if (version_num == @intFromEnum(LocresVer.Legacy)) try reader.setPos(0);
        if (version_num >= @intFromEnum(LocresVer.Compact)) try reader.setPos(25);
        if (version_num >= @intFromEnum(LocresVer.Optimized)) _ = try reader.uint32();  // Entry count

        const namespace_count: u32 = try reader.uint32();

        for (0..namespace_count) |_| {
            if (version_num >= @intFromEnum(LocresVer.Optimized)) _ = try reader.uint32();  // Namespace key hash

            var namespace: LocresNamespace = LocresNamespace.init(self.allocator, try reader.string());
            const key_count: u32 = try reader.uint32();

            for (0..key_count) |_| {
                if (version_num >= @intFromEnum(LocresVer.Optimized)) _ = try reader.uint32();  // String key hash

                const string_key: []const u8 = try reader.string();
                const source_string_hash: u32 = try reader.uint32();

                if (version_num >= @intFromEnum(LocresVer.Compact)) {
                    const string_index: u32 = try reader.uint32();
                    const entry: LocresEntry = LocresEntry.init(string_key, strings.items[string_index], source_string_hash);
                    
                    try namespace.set(string_key, entry);
                    continue;
                }
                const translation: []const u8 = try reader.string();
                const entry: LocresEntry = LocresEntry.init(string_key, translation, source_string_hash);
                try namespace.set(string_key, entry);
            }
            try locres.set(namespace.name, namespace);
        }
        return locres;
    }

    /// Writes the data to the `locres` file.
    pub fn write(self: *LocresFile, locres: Locres) !void {
        const file = std.fs.cwd().openFile(self.path, .{ .mode = .read_write }) catch
            try std.fs.cwd().createFile(self.path, .{ .read = true });

        var string_map = std.StringArrayHashMap(struct { count: u32, index: u32 }).init(self.allocator);
        defer string_map.deinit();

        try file.setEndPos(0);
        var writer: Writer = Writer.init(self.allocator, file);
        defer writer.deinit();

        const version_num: u2 = @intFromEnum(locres.version);

        // Write header
        if (version_num >= @intFromEnum(LocresVer.Compact)) {
            try writer.write(LOCRES_MAGIC);
            try writer.uint(version_num);
            try writer.write(&[8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 });
        }
        var ns_iter = locres.namespaces.iterator();
        var string_count: u32 = 0;

        // Populate string map
        while (ns_iter.next()) |ns_entry| {
            const namespace: *LocresNamespace = ns_entry.value_ptr;
            var entry_iter = namespace.entries.iterator();

            while (entry_iter.next()) |e_entry| {
                const entry: *LocresEntry = e_entry.value_ptr;
                const string: []const u8 = entry.translation;

                if (string_map.getPtr(string)) |info_ptr| {
                    info_ptr.count += 1;
                    continue;
                }
                try string_map.put(string, .{ .count = 1, .index = string_count });
                string_count += 1;
            }
        }
        ns_iter = locres.namespaces.iterator();

        while (ns_iter.next()) |ns_entry| {
            const namespace: *LocresNamespace = ns_entry.value_ptr;
            var entry_iter = namespace.entries.iterator();

            while (entry_iter.next()) |e_entry| {
                const entry: *LocresEntry = e_entry.value_ptr;
                const metadata = string_map.get(entry.translation).?;
                entry.string_index = metadata.index;
            }
        }

        // Legacy handling
        if (version_num == @intFromEnum(LocresVer.Legacy)) {
            try writer.uint32(locres.count());
            ns_iter = locres.namespaces.iterator();

            while (ns_iter.next()) |ns_entry| {
                const namespace: *LocresNamespace = ns_entry.value_ptr;
                try writer.string(namespace.name, true);
                try writer.uint32(namespace.count());
                var entry_iter = namespace.entries.iterator();

                while (entry_iter.next()) |e_entry| {
                    const entry: *LocresEntry = e_entry.value_ptr;
                    try writer.string(entry.key, false);
                    try writer.uint32(entry.hash_val);
                    try writer.string(entry.translation, false);
                }
            }
            return;
        }
        ns_iter = locres.namespaces.iterator();
        var key_count: u32 = 0;

        // Write keys
        while (ns_iter.next()) |ns_entry| {
            const namespace: *LocresNamespace = ns_entry.value_ptr;
            key_count += namespace.count();
        }
        if (version_num >= @intFromEnum(LocresVer.Optimized)) try writer.uint32(key_count);

        try writer.uint32(locres.count());
        ns_iter = locres.namespaces.iterator();

        while (ns_iter.next()) |ns_entry| {
            const namespace: *LocresNamespace = ns_entry.value_ptr;

            if (version_num == @intFromEnum(LocresVer.CityHash)) {
                try writer.uint32(try hash.hashUtf16ToU32(self.allocator, namespace.name));
            } else if (version_num >= @intFromEnum(LocresVer.Optimized)) {
                try writer.uint32(hash.crcHash32(namespace.name));
            }
            try writer.string(namespace.name, false);
            try writer.uint32(namespace.count());
            var entry_iter = namespace.entries.iterator();

            while (entry_iter.next()) |e_entry| {
                const entry: *LocresEntry = e_entry.value_ptr;

                if (version_num == @intFromEnum(LocresVer.CityHash)) {
                    try writer.uint32(try hash.hashUtf16ToU32(self.allocator, entry.key));
                } else if (version_num >= @intFromEnum(LocresVer.Optimized)) {
                    try writer.uint32(hash.crcHash32(entry.key));
                }
                try writer.string(entry.key, false);
                try writer.uint32(entry.hash_val);
                try writer.uint32(entry.string_index.?);
            }
        }
        // Write strings
        const tmp: u64 = try writer.getPos();
        try writer.setPos(17);
        try writer.uint64(tmp);
        try writer.setPos(tmp);
        try writer.uint32(@intCast(string_map.count()));
        var string_map_iter = string_map.iterator();

        while (string_map_iter.next()) |s_entry| {
            const string: []const u8 = s_entry.key_ptr.*;
            const metadata = s_entry.value_ptr.*;
            try writer.string(string, false);
            if (version_num >= @intFromEnum(LocresVer.Optimized)) try writer.uint32(metadata.count);
        }
    }
};
