const std = @import("std");
const testing = std.testing;
const c = @cImport({
    @cInclude("fast-lzma2.h");
    @cInclude("fl2_errors.h");
});

test "streaming compression basic" {
    const allocator = testing.allocator;

    const stream = c.FL2_createCStream();
    try testing.expect(stream != null);
    defer c.FL2_freeCStream(stream);

    const init_result = c.FL2_initCStream(stream, 5);
    try testing.expect(c.FL2_isError(init_result) == 0);

    const input = "This is test data for streaming compression.";
    var in_buffer = c.FL2_inBuffer{
        .src = input.ptr,
        .size = input.len,
        .pos = 0,
    };

    const out_capacity = 1000;
    const output = try allocator.alloc(u8, out_capacity);
    defer allocator.free(output);

    var out_buffer = c.FL2_outBuffer{
        .dst = output.ptr,
        .size = out_capacity,
        .pos = 0,
    };

    const compress_result = c.FL2_compressStream(stream, &out_buffer, &in_buffer);
    try testing.expect(c.FL2_isError(compress_result) == 0);

    const end_result = c.FL2_endStream(stream, &out_buffer);
    try testing.expect(c.FL2_isError(end_result) == 0);
    try testing.expect(end_result == 0);

    const compressed_size = out_buffer.pos;
    try testing.expect(compressed_size > 0);

    const decompressed = try allocator.alloc(u8, input.len);
    defer allocator.free(decompressed);

    const decompress_result = c.FL2_decompress(decompressed.ptr, input.len, output.ptr, compressed_size);

    try testing.expect(c.FL2_isError(decompress_result) == 0);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "streaming decompression basic" {
    const allocator = testing.allocator;

    const input = "Test data for streaming decompression.";
    const compressed_capacity = c.FL2_compressBound(input.len);
    const compressed = try allocator.alloc(u8, compressed_capacity);
    defer allocator.free(compressed);

    const compressed_size = c.FL2_compress(compressed.ptr, compressed_capacity, input.ptr, input.len, 5);
    try testing.expect(c.FL2_isError(compressed_size) == 0);

    const dstream = c.FL2_createDStream();
    try testing.expect(dstream != null);
    defer _ = c.FL2_freeDStream(dstream);

    const init_result = c.FL2_initDStream(dstream);
    try testing.expect(c.FL2_isError(init_result) == 0);

    var in_buffer = c.FL2_inBuffer{
        .src = compressed.ptr,
        .size = compressed_size,
        .pos = 0,
    };

    const decompressed = try allocator.alloc(u8, input.len);
    defer allocator.free(decompressed);

    var out_buffer = c.FL2_outBuffer{
        .dst = decompressed.ptr,
        .size = input.len,
        .pos = 0,
    };

    const decompress_result = c.FL2_decompressStream(dstream, &out_buffer, &in_buffer);
    try testing.expect(c.FL2_isError(decompress_result) == 0);

    try testing.expectEqual(input.len, out_buffer.pos);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "chunked streaming compression" {
    const allocator = testing.allocator;

    const stream = c.FL2_createCStream();
    try testing.expect(stream != null);
    defer c.FL2_freeCStream(stream);

    const init_result = c.FL2_initCStream(stream, 5);
    try testing.expect(c.FL2_isError(init_result) == 0);

    const chunk1 = "First chunk of data. ";
    const chunk2 = "Second chunk of data. ";
    const chunk3 = "Third chunk of data.";

    const out_capacity = 1000;
    const output = try allocator.alloc(u8, out_capacity);
    defer allocator.free(output);

    var out_buffer = c.FL2_outBuffer{
        .dst = output.ptr,
        .size = out_capacity,
        .pos = 0,
    };

    const chunks = [_][]const u8{ chunk1, chunk2, chunk3 };
    for (chunks) |chunk| {
        var in_buffer = c.FL2_inBuffer{
            .src = chunk.ptr,
            .size = chunk.len,
            .pos = 0,
        };

        const result = c.FL2_compressStream(stream, &out_buffer, &in_buffer);
        try testing.expect(c.FL2_isError(result) == 0);
        try testing.expectEqual(chunk.len, in_buffer.pos);
    }

    const end_result = c.FL2_endStream(stream, &out_buffer);
    try testing.expect(c.FL2_isError(end_result) == 0);
    try testing.expectEqual(@as(usize, 0), end_result);

    const full_input = chunk1 ++ chunk2 ++ chunk3;
    const decompressed = try allocator.alloc(u8, full_input.len);
    defer allocator.free(decompressed);

    const decompress_result = c.FL2_decompress(decompressed.ptr, full_input.len, output.ptr, out_buffer.pos);

    try testing.expect(c.FL2_isError(decompress_result) == 0);
    try testing.expectEqualSlices(u8, full_input, decompressed);
}

test "streaming with small output buffer" {
    const allocator = testing.allocator;

    const stream = c.FL2_createCStream();
    try testing.expect(stream != null);
    defer c.FL2_freeCStream(stream);

    const init_result = c.FL2_initCStream(stream, 5);
    try testing.expect(c.FL2_isError(init_result) == 0);

    const input = "A" ** 1000;
    var in_buffer = c.FL2_inBuffer{
        .src = input.ptr,
        .size = input.len,
        .pos = 0,
    };

    const small_buffer_size = 50;
    const small_buffer = try allocator.alloc(u8, small_buffer_size);
    defer allocator.free(small_buffer);

    var compressed_data = std.ArrayList(u8).init(allocator);
    defer compressed_data.deinit();

    while (in_buffer.pos < in_buffer.size) {
        var out_buffer = c.FL2_outBuffer{
            .dst = small_buffer.ptr,
            .size = small_buffer_size,
            .pos = 0,
        };

        const result = c.FL2_compressStream(stream, &out_buffer, &in_buffer);
        try testing.expect(c.FL2_isError(result) == 0);

        try compressed_data.appendSlice(small_buffer[0..out_buffer.pos]);
    }

    var finish_needed: usize = 1;
    while (finish_needed != 0) {
        var out_buffer = c.FL2_outBuffer{
            .dst = small_buffer.ptr,
            .size = small_buffer_size,
            .pos = 0,
        };

        finish_needed = c.FL2_endStream(stream, &out_buffer);
        try testing.expect(c.FL2_isError(finish_needed) == 0);

        try compressed_data.appendSlice(small_buffer[0..out_buffer.pos]);
    }

    const decompressed = try allocator.alloc(u8, input.len);
    defer allocator.free(decompressed);

    const decompress_result = c.FL2_decompress(decompressed.ptr, input.len, compressed_data.items.ptr, compressed_data.items.len);

    try testing.expect(c.FL2_isError(decompress_result) == 0);
    try testing.expectEqualSlices(u8, input, decompressed);
}

test "streaming reset and reuse" {
    const allocator = testing.allocator;

    const stream = c.FL2_createCStream();
    try testing.expect(stream != null);
    defer c.FL2_freeCStream(stream);

    const inputs = [_][]const u8{
        "First compression session data.",
        "Second compression session with different data.",
    };

    for (inputs) |input| {
        const init_result = c.FL2_initCStream(stream, 5);
        try testing.expect(c.FL2_isError(init_result) == 0);

        var in_buffer = c.FL2_inBuffer{
            .src = input.ptr,
            .size = input.len,
            .pos = 0,
        };

        const out_capacity = 1000;
        const output = try allocator.alloc(u8, out_capacity);
        defer allocator.free(output);

        var out_buffer = c.FL2_outBuffer{
            .dst = output.ptr,
            .size = out_capacity,
            .pos = 0,
        };

        const compress_result = c.FL2_compressStream(stream, &out_buffer, &in_buffer);
        try testing.expect(c.FL2_isError(compress_result) == 0);

        const end_result = c.FL2_endStream(stream, &out_buffer);
        try testing.expect(c.FL2_isError(end_result) == 0);

        const decompressed = try allocator.alloc(u8, input.len);
        defer allocator.free(decompressed);

        const decompress_result = c.FL2_decompress(decompressed.ptr, input.len, output.ptr, out_buffer.pos);

        try testing.expect(c.FL2_isError(decompress_result) == 0);
        try testing.expectEqualSlices(u8, input, decompressed);
    }
}

test "streaming compression recommended sizes" {
    const in_size: usize = 65536;
    const out_size: usize = 131072;

    try testing.expect(in_size > 0);
    try testing.expect(out_size > 0);

    const allocator = testing.allocator;

    const stream = c.FL2_createCStream();
    try testing.expect(stream != null);
    defer c.FL2_freeCStream(stream);

    const init_result = c.FL2_initCStream(stream, 5);
    try testing.expect(c.FL2_isError(init_result) == 0);

    const input = try allocator.alloc(u8, in_size);
    defer allocator.free(input);
    for (input, 0..) |*byte, i| {
        byte.* = @truncate(i % 256);
    }

    var in_buffer = c.FL2_inBuffer{
        .src = input.ptr,
        .size = in_size,
        .pos = 0,
    };

    const output = try allocator.alloc(u8, out_size);
    defer allocator.free(output);

    var out_buffer = c.FL2_outBuffer{
        .dst = output.ptr,
        .size = out_size,
        .pos = 0,
    };

    const compress_result = c.FL2_compressStream(stream, &out_buffer, &in_buffer);
    try testing.expect(c.FL2_isError(compress_result) == 0);
}
