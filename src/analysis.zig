const std = @import("std");
const lsp = @import("lsp");
const zig = @import("zig.zig");

pub const Result = struct {
    name: []const u8,
    output: []const u8 = "",
    status: bool,
};

pub const State = struct {
    const Self = @This();

    test_results: std.AutoArrayHashMap(usize, Result),
    arena: ?std.heap.ArenaAllocator = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .test_results = std.AutoArrayHashMap(usize, Result).init(allocator),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.clear(allocator);
        self.test_results.deinit();
    }

    fn clear(self: *Self) void {
        self.test_results.clearAndFree();
        if (self.arena) |a| {
            a.deinit();
            self.arena = null;
        }
    }

    pub fn update(self: *Self, allocator: std.mem.Allocator, doc: lsp.Document) !void {
        self.clear();
        var lines = std.mem.splitScalar(u8, doc.text, '\n');
        const filename = uriToFilename(doc.uri);

        self.arena = std.heap.ArenaAllocator.init(allocator);
        const results = try zig.Zig.run(self.arena.?.allocator(), filename);

        var i: usize = 0;
        while (lines.next()) |line| : (i += 1) {
            if (!std.mem.startsWith(u8, line, "test \"")) continue;
            const test_name = getTestName(line);
            for (results) |r| {
                if (std.mem.eql(u8, r.name, test_name)) {
                    try self.test_results.put(i, r);
                    break;
                }
            }
        }
    }
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
