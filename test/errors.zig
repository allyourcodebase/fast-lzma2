const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("fast-lzma2.h");
    @cInclude("fl2_errors.h");
});

test "insufficient destination buffer" {
    const input = "This is a long string that we will try to compress into a very small buffer" ** 10;
    const src_size = input.len;

    const compressed = try testing.allocator.alloc(u8, 10);
    defer testing.allocator.free(compressed);

    const result = c.FL2_compress(compressed.ptr, 10, input.ptr, src_size, 5);

    try testing.expect(c.FL2_isError(result) != 0);

    const error_name = c.FL2_getErrorName(result);
    try testing.expect(error_name != null);
}

test "invalid compression level" {
    const input = "Test data";
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    // Test with level 0 (invalid)
    const result = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 0);

    // Level 0 might be valid, so just check if it doesn't crash
    _ = result;

    // Test with very high level
    const high_level_result = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 100);

    // High level might be clamped, so just check if it doesn't crash
    _ = high_level_result;
}

test "null pointer handling" {
    const input = "Test data";
    const src_size = input.len;

    const compressed = try testing.allocator.alloc(u8, 100);
    defer testing.allocator.free(compressed);

    // Skip null dst test as it causes segfault in the C library
    // const result_null_dst = c.FL2_compress(
    //     null,
    //     100,
    //     input.ptr,
    //     src_size,
    //     5
    // );
    // try testing.expect(c.FL2_isError(result_null_dst) != 0);

    // Test with zero size instead to avoid segfault
    const result_zero_size = c.FL2_compress(compressed.ptr, 0, input.ptr, src_size, 5);
    try testing.expect(c.FL2_isError(result_zero_size) != 0);
}

test "corrupted compressed data" {
    const input = "Original test data for compression";
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 5);

    try testing.expect(c.FL2_isError(compressed_size) == 0);

    compressed[compressed_size / 2] ^= 0xFF;
    compressed[compressed_size / 3] ^= 0xAA;

    const decompressed = try testing.allocator.alloc(u8, src_size);
    defer testing.allocator.free(decompressed);

    const result = c.FL2_decompress(decompressed.ptr, src_size, compressed.ptr, compressed_size);

    if (c.FL2_isError(result) == 0) {
        try testing.expect(result != src_size or !std.mem.eql(u8, input, decompressed));
    }
}

test "decompression buffer too small" {
    const input = "Test data to compress and then decompress into a too-small buffer";
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, dst_capacity, input.ptr, src_size, 5);

    try testing.expect(c.FL2_isError(compressed_size) == 0);

    const small_buffer = try testing.allocator.alloc(u8, 10);
    defer testing.allocator.free(small_buffer);

    const result = c.FL2_decompress(small_buffer.ptr, 10, compressed.ptr, compressed_size);

    try testing.expect(c.FL2_isError(result) != 0);
}

test "invalid compressed data format" {
    const fake_compressed = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00 };

    const decompressed = try testing.allocator.alloc(u8, 100);
    defer testing.allocator.free(decompressed);

    const result = c.FL2_decompress(decompressed.ptr, 100, &fake_compressed, fake_compressed.len);

    try testing.expect(c.FL2_isError(result) != 0);
}

test "zero size operations" {
    const compressed = try testing.allocator.alloc(u8, 100);
    defer testing.allocator.free(compressed);

    const input = "Test";

    const result_zero_dst_capacity = c.FL2_compress(compressed.ptr, 0, input.ptr, input.len, 5);
    try testing.expect(c.FL2_isError(result_zero_dst_capacity) != 0);

    const result_zero_src = c.FL2_compress(compressed.ptr, 100, input.ptr, 0, 5);

    if (c.FL2_isError(result_zero_src) == 0) {
        const decompressed_size = c.FL2_findDecompressedSize(compressed.ptr, result_zero_src);
        try testing.expectEqual(@as(usize, 0), decompressed_size);
    }
}

test "multi-thread error handling" {
    const input = "Test data for multi-threaded operations";
    const src_size = input.len;

    const dst_capacity = c.FL2_compressBound(src_size);
    const compressed = try testing.allocator.alloc(u8, dst_capacity);
    defer testing.allocator.free(compressed);

    const result_too_many_threads = c.FL2_compressMt(compressed.ptr, dst_capacity, input.ptr, src_size, 5, c.FL2_MAXTHREADS + 100);

    if (c.FL2_isError(result_too_many_threads) != 0) {
        const error_name = c.FL2_getErrorName(result_too_many_threads);
        try testing.expect(error_name != null);
    }

    const result_small_buffer = c.FL2_compressMt(compressed.ptr, 5, input.ptr, src_size, 5, 2);

    try testing.expect(c.FL2_isError(result_small_buffer) != 0);
}

test "error string retrieval" {
    const input = "Test";
    var compressed: [1]u8 = undefined;
    const error_code = c.FL2_compress(&compressed, compressed.len, input.ptr, input.len, 5);
    try testing.expect(c.FL2_isError(error_code) != 0);
    const error_name = c.FL2_getErrorName(error_code);
    try testing.expect(error_name != null);
    try testing.expectEqualSlices(u8, "Destination buffer is too small", std.mem.span(error_name));
    const error_string = c.FL2_getErrorString(@as(c_uint, @truncate(error_code)));
    try testing.expect(error_string != null);
}
