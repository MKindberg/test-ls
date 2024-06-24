const std = @import("std");
const lsp = @import("lsp");

pub const State = struct {
    const RunResult = std.process.Child.RunResult;
    const Self = @This();

    test_results: std.AutoArrayHashMap(usize, RunResult),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .test_results = std.AutoArrayHashMap(usize, RunResult).init(allocator),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.clear(allocator);
        self.test_results.deinit();
    }

    fn clear(self: *Self, allocator: std.mem.Allocator) void {
        var entries = self.test_results.iterator();
        while (entries.next()) |entry| {
            allocator.free(entry.value_ptr.stdout);
            allocator.free(entry.value_ptr.stderr);
        }
        self.test_results.clearAndFree();
    }

    pub fn update(self: *Self, allocator: std.mem.Allocator, doc: lsp.Document) !void {
        self.clear(allocator);
        var lines = std.mem.splitScalar(u8, doc.text, '\n');

        var i: usize = 0;
        while (lines.next()) |line| : (i += 1) {
            if (!std.mem.startsWith(u8, line, "test ")) continue;
            const test_name = getTestName(line);
            const filename = uriToFilename(doc.uri);
            try self.test_results.put(i, try runTest(allocator, filename, test_name));
        }
    }
};

const TestResult = struct {
    const RunResult = std.process.Child.RunResult;

    result: RunResult,
};

fn getTestName(line: []const u8) []const u8 {
    const name_start = std.mem.indexOfScalar(u8, line, '"').?;
    const name_end = std.mem.indexOfScalarPos(u8, line, name_start + 1, '"').?;
    return line[name_start + 1 .. name_end];
}

fn uriToFilename(uri: []const u8) []const u8 {
    const prefix = "file://";
    std.debug.assert(std.mem.startsWith(u8, uri, prefix));
    return uri[prefix.len..];
}

fn runTest(allocator: std.mem.Allocator, file: []const u8, name: []const u8) !std.process.Child.RunResult {
    const argv = [_][]const u8{
        "zig",
        "test",
        file,
        "--test-filter",
        name,
    };
    std.log.debug("Running test: {s}\n", .{name});
    return std.process.Child.run(.{ .allocator = allocator, .argv = &argv });
}
