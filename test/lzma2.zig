const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("fast-lzma2.h");
    @cInclude("fl2_errors.h");
});

test "version check" {
    const version_num = c.FL2_versionNumber();
    try testing.expect(version_num > 0);

    const version_str = c.FL2_versionString();
    try testing.expect(version_str != null);
}

test "basic compression and decompression" {
    const input = "Hello, World! This is a test string for LZMA2 compression.";
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 9);

    try testing.expect(c.FL2_isError(compressed_size) == 0);
    try testing.expect(compressed_size > 0);

    const decompressed_size = c.FL2_findDecompressedSize(compressed.ptr, compressed_size);
    try testing.expect(c.FL2_isError(decompressed_size) == 0);
    try testing.expectEqual(src_size, decompressed_size);

    const decompressed = try testing.allocator.alloc(u8, decompressed_size);
    defer testing.allocator.free(decompressed);

    const actual_decompressed = c.FL2_decompress(decompressed.ptr, decompressed_size, compressed.ptr, compressed_size);

    try testing.expect(c.FL2_isError(actual_decompressed) == 0);
    try testing.expectEqual(src_size, actual_decompressed);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "empty input compression" {
    const input = "";
    const src_size = input.len;

    const dst_capacity = 100;
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 5);

    try testing.expect(c.FL2_isError(compressed_size) == 0);

    const decompressed_size = c.FL2_findDecompressedSize(compressed.ptr, compressed_size);
    try testing.expect(c.FL2_isError(decompressed_size) == 0);
    try testing.expectEqual(@as(usize, 0), decompressed_size);
}

test "large data compression" {
    const size = 1024 * 1024;
    const input = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(input);

    for (input, 0..) |*byte, i| {
        byte.* = @truncate(i % 256);
    }

    const dst_capacity = c.FL2_compressBound(size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, size, 5);

    try testing.expect(c.FL2_isError(compressed_size) == 0);
    try testing.expect(compressed_size > 0);

    const decompressed = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(decompressed);

    const actual_decompressed = c.FL2_decompress(decompressed.ptr, size, compressed.ptr, compressed_size);

    try testing.expect(c.FL2_isError(actual_decompressed) == 0);
    try testing.expectEqual(size, actual_decompressed);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "compression levels" {
    const input = "The quick brown fox jumps over the lazy dog. " ** 10;
    const src_size = input.len;

    var prev_size: usize = std.math.maxInt(usize);

    const levels = [_]c_int{ 1, 3, 5, 7, 9 };
    for (levels) |level| {
        const dst_capacity = c.FL2_compressBound(src_size);
        const compressed = try testing.allocator.alloc(u8, dst_capacity);
        defer testing.allocator.free(compressed);

        const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, level);

        try testing.expect(c.FL2_isError(compressed_size) == 0);

        if (level > 1) {
            try testing.expect(compressed_size <= prev_size);
        }
        prev_size = compressed_size;

        const decompressed = try testing.allocator.alloc(u8, src_size);
        defer testing.allocator.free(decompressed);

        const actual_decompressed = c.FL2_decompress(decompressed.ptr, src_size, compressed.ptr, compressed_size);

        try testing.expect(c.FL2_isError(actual_decompressed) == 0);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
}

test "multi-threaded compression" {
    const input = "Test data for multi-threaded compression. " ** 100;
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compressMt(compressed.ptr, dst_capacity, input.ptr, src_size, 5, 2);

    try testing.expect(c.FL2_isError(compressed_size) == 0);

    const decompressed = try testing.allocator.alloc(u8, src_size);
    defer testing.allocator.free(decompressed);

    const actual_decompressed = c.FL2_decompressMt(decompressed.ptr, src_size, compressed.ptr, compressed_size, 2);

    try testing.expect(c.FL2_isError(actual_decompressed) == 0);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "random binary data" {
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    const size = 10000;
    const input = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(input);
    random.bytes(input);

    const dst_capacity = c.FL2_compressBound(size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, size, 5);

    try testing.expect(c.FL2_isError(compressed_size) == 0);

    const decompressed = try testing.allocator.alloc(u8, size);
    defer testing.allocator.free(decompressed);

    const actual_decompressed = c.FL2_decompress(decompressed.ptr, size, compressed.ptr, compressed_size);

    try testing.expect(c.FL2_isError(actual_decompressed) == 0);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "repetitive data compression" {
    const pattern = "AAAA";
    const input = pattern ** 1000;
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 5);

    try testing.expect(c.FL2_isError(compressed_size) == 0);
    try testing.expect(compressed_size < src_size / 10);

    const decompressed = try testing.allocator.alloc(u8, src_size);
    defer testing.allocator.free(decompressed);

    const actual_decompressed = c.FL2_decompress(decompressed.ptr, src_size, compressed.ptr, compressed_size);

    try testing.expect(c.FL2_isError(actual_decompressed) == 0);
    try testing.expectEqualSlices(u8, input, decompressed);
}
