const std = @import("std");
const lsp = @import("lsp");

const Lsp = lsp.Lsp(void);

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const server_data = lsp.types.ServerData{
        .capabilities = .{
            .hoverProvider = true,
        },
        .serverInfo = .{
            .name = "censor-ls",
            .version = "0.1.0",
        },
    };
    var server = Lsp.init(allocator, server_data, {});
    defer server.deinit();

    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(allocator: std.mem.Allocator, context: Lsp.Context, request: lsp.types.Request.Hover.Params, id: i32) void {
    const line = context.document.getLine(request.position).?;
    if (std.mem.startsWith(u8, line, "test")) {
        const filename = uriToFilename(request.textDocument.uri);
        const name_start = std.mem.indexOfScalar(u8, line, '"').?;
        const name_end = name_start + std.mem.indexOfScalarPos(u8, line, name_start, '"').?;
        const test_name = line[name_start + 1 .. name_end];
        const test_data = runTest(allocator, filename, test_name) catch return;
        defer allocator.free(test_data.stdout);
        defer allocator.free(test_data.stderr);

        var message = std.ArrayList(u8).init(allocator);
        defer message.deinit();

        message.writer().print("Result: {any}\n\n", .{test_data.term.Exited}) catch unreachable;
        if (test_data.stdout.len > 0) message.writer().print("stdout:\n{s}\n\n", .{test_data.stdout}) catch unreachable;
        if (test_data.stderr.len > 0) message.writer().print("stderr:\n{s}\n\n", .{test_data.stderr}) catch unreachable;

        const response = lsp.types.Response.Hover.init(id, message.items);

        lsp.writeResponse(allocator, response) catch unreachable;
    }
}

fn uriToFilename(uri: []const u8) []const u8 {
    return uri[7..];
}

fn runTest(allocator: std.mem.Allocator, file: []const u8, name: []const u8) !std.process.Child.RunResult {
    const argv = [_][]const u8{
        "zig",
        "test",
        file,
        "--test-filter",
        name,
    };
    return std.process.Child.run(.{ .allocator = allocator, .argv = &argv });
}

test "simple test" {}
