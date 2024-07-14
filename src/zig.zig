const std = @import("std");
const Result = @import("analysis.zig").Result;

pub const Zig = struct {
    pub fn run(allocator: std.mem.Allocator, file: []const u8) ![]const Result {
        const test_res = try execute(allocator, file);
        var results = std.ArrayList(Result).init(allocator);

        var num_tests: usize = 0;
        var prev: usize = 0;
        var start: usize = 0;
        var end: usize = 0;
        var passed: usize = 0;
        var failed: usize = 0;
        var current_test: ?Result = null;
        while (true) {
            end = std.mem.indexOfScalarPos(u8, test_res.stderr, start, '\n') orelse break;
            const line = test_res.stderr[start..end];
            if (parserHeader(line, &num_tests, 1 + passed + failed)) |header| {
                if (current_test) |*t| {
                    t.output = test_res.stderr[prev..start];
                    results.append(t.*) catch unreachable;
                }
                prev = start;
                current_test = .{ .name = header.test_name, .status = header.status };
                if (header.status) {
                    passed += 1;
                } else {
                    failed += 1;
                }
            }
            var buf: [32]u8 = undefined;
            const end_pattern = std.fmt.bufPrint(&buf, "{} passed; 0 skipped; {} failed.", .{ passed, failed }) catch unreachable;
            if (std.mem.eql(u8, line, end_pattern)) {
                std.debug.print("end\n", .{});
                break;
            }
            start = end + 1;
        }
        if (current_test) |*t| {
            t.output = test_res.stderr[prev..start];
            results.append(t.*) catch unreachable;
        }
        return results.items;
    }

    fn execute(allocator: std.mem.Allocator, file: []const u8) !std.process.Child.RunResult {
        const argv = [_][]const u8{
            "zig",
            "test",
            file,
        };
        return std.process.Child.run(.{ .allocator = allocator, .argv = &argv });
    }

    fn parserHeader(line: []const u8, num_tests: *usize, test_num: usize) ?struct { test_name: []const u8, status: bool } {
        if (test_num == 1) {
            if (!std.mem.startsWith(u8, line, "1/")) return null;
            const n = line[2..std.mem.indexOfScalar(u8, line, ' ').?];
            num_tests.* = std.fmt.parseInt(usize, n, 10) catch unreachable;
        } else {
            var buf: [10]u8 = undefined;
            const line_start = std.fmt.bufPrint(&buf, "{}/{}", .{ test_num, num_tests.* }) catch unreachable;
            if (!std.mem.startsWith(u8, line, line_start)) return null;
        }

        const test_name_start = std.mem.indexOf(u8, line, ".test.").? + ".test.".len;
        const test_name_end = std.mem.indexOf(u8, line, "...").?;
        const test_name = line[test_name_start..test_name_end];
        return .{
            .test_name = test_name,
            .status = std.mem.endsWith(u8, line, "OK"),
        };
    }
};
