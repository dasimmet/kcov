//! This is bin-to-c-source.py ported to Zig:
//! https://github.com/SimonKagstrom/kcov/blob/master/src/bin-to-c-source.py

const std = @import("std");

fn generate(writer: std.io.AnyWriter, data: []const u8, base_name: []const u8) !void {
    try writer.print("const uint8_t {s}_data_raw[] = {{\n", .{base_name});

    for (data, 0..) |c, i| {
        // more optimized version of:
        // try writer.print("0x{x:0>2},", .{c});
        const charset = "0123456789abcdef";
        try writer.writeAll(&.{ '0', 'x', charset[c >> 4], charset[c & 15], ',' });

        if (i % 20 == 19) try writer.writeByte('\n');
    }

    try writer.print(
        \\
        \\}};
        \\GeneratedData {0s}_data({0s}_data_raw, sizeof({0s}_data_raw));
        \\
    , .{base_name});
}

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = general_purpose_allocator.deinit();
    const gpa = general_purpose_allocator.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var buffered_stdout = std.io.bufferedWriter(std.io.getStdOut().writer());
    const stdout = buffered_stdout.writer();

    const stderr = std.io.getStdErr().writer();

    if (args.len < 3 or (args.len - 1) % 2 != 0) {
        try stderr.print("Usage: {s} <file> <base-name> [<file2> <base-name2>]\n", .{args[0]});
        std.process.exit(1);
    }

    try stdout.writeAll(
        \\#include <stdint.h>
        \\#include <stdlib.h>
        \\#include <generated-data-base.hh>
        \\using namespace kcov;
        \\
    );

    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        const file = args[i];
        const base_name = args[i + 1];

        const data = try std.fs.cwd().readFileAlloc(gpa, file, std.math.maxInt(usize));
        defer gpa.free(data);

        try generate(stdout.any(), data, base_name);
    }

    try buffered_stdout.flush();
}
