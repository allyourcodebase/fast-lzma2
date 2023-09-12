const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    if (b.option(
        []const u8,
        "multitarget",
        "Create multiple targets, works around an issue with multiple targets",
    )) |multitarget| {
        var it = std.mem.split(u8, multitarget, ",");
        while (it.next()) |target_string| {
            const target = std.zig.CrossTarget.parse(.{ .arch_os_abi = target_string }) catch |err|
                std.debug.panic("failed to parse target '{s}' with {s}", .{target_string, @errorName(err)});
            const name = std.mem.concat(b.allocator, u8, &.{"fast-lzma2-", target_string}) catch @panic("OOM");
            addLib(b, name, target, optimize);
        }
    } else {
        const target = b.standardTargetOptions(.{});
        addLib(b, "fast-lzma2", target, optimize);
    }
}

fn addLib(
    b: *std.Build,
    name: []const u8,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
) void {
    const lib = b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });
    lib.addCSourceFiles(&[_][]const u8 {
        "dict_buffer.c",
        "fl2_common.c",
        "fl2_compress.c",
        "fl2_decompress.c",
        "fl2_pool.c",
        "fl2_threading.c",
        "lzma2_dec.c",
        "lzma2_enc.c",
        "radix_bitpack.c",
        "radix_mf.c",
        "radix_struct.c",
        "range_enc.c",
        "util.c",
        "xxhash.c",
        }, &[_][]const u8 {
        "-Wall",
        "-O2",
        "-pthread",
        // note: project should be fixed to not need this
        "-fno-sanitize=undefined",
    });
    lib.linkLibC();
    lib.installHeader("fast-lzma2.h", "fast-lzma2.h");
    lib.installHeader("fl2_errors.h", "fl2_errors.h");
    b.installArtifact(lib);
}
