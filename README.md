# zLocres

[![License](https://img.shields.io/github/license/AceHanded/zlocres?style=for-the-badge)](https://github.com/AceHanded/zlocres/blob/main/LICENSE)
[![Zig Version](https://img.shields.io/badge/zig-0.14.1-yellow?style=for-the-badge&logo=zig)](https://ziglang.org/)
[![GitHubStars](https://img.shields.io/github/stars/AceHanded/zlocres?style=for-the-badge&logo=github&labelColor=black)](https://github.com/AceHanded/zlocres)
[![BuyMeACoffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/acehand)

A Zig package for handling `.locmeta` and `.locres` files.

## Installation

First, add the package as a dependency to your `build.zig.zon` with the following command.

```bash
zig fetch --save git+https://github.com/AceHanded/zlocres.git
```

Next, add the following code to your `build.zig`.

```zig
const zlocres = b.dependency("zlocres", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zlocres", zlocres.module("zlocres"));
```

## Examples

> [!NOTE]
> The examples aim to showcase the usage of the package and therefore may not necessarily represent the "best" ways to use it.

### Hashing

```zig
const std = @import("std");
const zlocres = @import("zlocres");
const hash = zlocres.hash;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    std.debug.print("0x{x}\n", .{try hash.hashUtf16ToU32(allocator, "example")});  // 0xbf7a4ae6
    std.debug.print("0x{x}\n", .{hash.crcHash32("example")});  // 0x7c20ea98
}
```

### Locmeta

```zig
const std = @import("std");
const zlocres = @import("zlocres");
const LocmetaFile = zlocres.loc.LocmetaFile;
const LocmetaVer = zlocres.loc.LocmetaVer;
const Locmeta = zlocres.loc.Locmeta;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var locmeta_file = try LocmetaFile.init(allocator, "./Test.locmeta");
    const locmeta_res = try locmeta_file.read();
    std.debug.print("{}\n", .{locmeta_res.version});  // loc.LocmetaVer.V1 (assuming latest version)

    const new_locmeta = Locmeta.init(
        LocmetaVer.V1,  // version
        "en",  // native_culture
        "en/Test2.locres",  // native_locres
        &[2][]const u8{ "en", "fi" }  // compiled_cultures
    );
    var locmeta_file2 = try LocmetaFile.init(allocator, "./Test2.locmeta");
    try locmeta_file2.write(new_locmeta);
    const locmeta_res2 = try locmeta_file2.read();
    std.debug.print("{}\n", .{locmeta_res2.version});  // loc.LocmetaVer.V1
}
```

### Locres

```zig
const std = @import("std");
const zlocres = @import("zlocres");
const hash = zlocres.hash;
const LocresFile = zlocres.loc.LocresFile;
const LocresVer = zlocres.loc.LocresVer;
const LocresNamespace = zlocres.loc.LocresNamespace;
const LocresEntry = zlocres.loc.LocresEntry;
const Locres = zlocres.loc.Locres;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var locres_file = try LocresFile.init(allocator, "./Test.locres");
    var locres_res = try locres_file.read();
    defer locres_res.deinit();  // Remember to free the namespaces!

    std.debug.print("{}\n", .{locres_res.version});  // loc.LocresVer.CityHash (assuming latest version)

    const new_entry_key = "ExampleEntry";
    const new_entry = LocresEntry.init(
        new_entry_key,  // key
        "example",  // translation
        try hash.hashUtf16ToU32(allocator, new_entry_key)  // hash_val
    );

    var new_namespace = LocresNamespace.init(
        allocator,  // allocator
        "ExampleNamespace"  // name
    );
    try new_namespace.set(new_entry_key, new_entry);

    var new_locres = Locres.init(
        allocator,  // allocator
        LocresVer.CityHash  // version
    );
    defer new_locres.deinit();

    try new_locres.set(new_namespace.name, new_namespace);
    var locres_file2 = try LocresFile.init(allocator, "./Test2.locres");
    try locres_file2.write(new_locres);
    var locres_res2 = try locres_file2.read();
    defer locres_res2.deinit();

    std.debug.print("{}\n", .{locres_res2.version});  // loc.LocresVer.CityHash
}
```
