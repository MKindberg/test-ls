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

    server.registerDocOpenCallback(handleOpen);
    server.registerDocSaveCallback(handleSave);
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

fn handleOpen(allocator: std.mem.Allocator, context: Lsp.Context, notification: lsp.types.Notification.DidOpenTextDocument.Params) void {
    sendNotification(allocator, notification.textDocument.uri, context.document);
}

fn handleSave(allocator: std.mem.Allocator, context: Lsp.Context, notification: lsp.types.Notification.DidSaveTextDocument.Params) void {
    sendNotification(allocator, notification.textDocument.uri, context.document);
}

fn uriToFilename(uri: []const u8) []const u8 {
    return uri[7..];
}

fn testName(line: []const u8) []const u8 {
    const name_start = std.mem.indexOfScalar(u8, line, '"').?;
    const name_end = name_start + std.mem.indexOfScalarPos(u8, line, name_start, '"').?;
    return line[name_start + 1 .. name_end];
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

fn createDiagnostic(line: usize, pass: bool) lsp.types.Diagnostic {
    if (pass) {
        return lsp.types.Diagnostic{
            .range = .{
                .start = .{
                    .line = line,
                    .character = 0,
                },
                .end = .{
                    .line = line,
                    .character = 0,
                },
            },
            .severity = 3,
            .source = "test-ls",
            .message = "Test passed",
        };
    }
    return lsp.types.Diagnostic{
        .range = .{
            .start = .{
                .line = line,
                .character = 0,
            },
            .end = .{
                .line = line,
                .character = 0,
            },
        },
        .severity = 1,
        .source = "test-ls",
        .message = "Test failed",
    };
}

fn sendNotification(allocator: std.mem.Allocator, uri: []const u8, document: lsp.Document) void {
    var test_lines = std.ArrayList(usize).init(allocator);
    defer test_lines.deinit();
    var lines = std.mem.splitScalar(u8, document.text, '\n');

    var i: usize = 0;
    while (lines.next()) |line| : (i += 1) {
        if (std.mem.startsWith(u8, line, "test")) {
            test_lines.append(i) catch unreachable;
        }
    }

    const filename = uriToFilename(uri);
    var diagnostics = std.ArrayList(lsp.types.Diagnostic).init(allocator);
    defer diagnostics.deinit();
    for (test_lines.items) |test_line| {
        const line = document.getLine(lsp.types.Position{ .line = test_line, .character = 0 }).?;
        const test_name = testName(line);

        const test_result = runTest(allocator, filename, test_name) catch continue;
        allocator.free(test_result.stdout);
        allocator.free(test_result.stderr);
        const diagnostic = createDiagnostic(test_line, test_result.term.Exited == 0);
        diagnostics.append(diagnostic) catch unreachable;
    }

    const response = lsp.types.Notification.PublishDiagnostics{ .method = "textDocument/publishDiagnostics", .params = .{
        .uri = uri,
        .diagnostics = diagnostics.items,
    } };

    lsp.writeResponse(allocator, response) catch unreachable;
}
