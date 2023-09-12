const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    {
        const lib = b.addStaticLibrary(.{
            .name = "fast-lzma2",
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
}
