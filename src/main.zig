const std = @import("std");
const lsp = @import("lsp");

const State = @import("analysis.zig").State;
const Lsp = lsp.Lsp(State);

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
    var server = Lsp.init(allocator, server_data);
    defer server.deinit();

    server.registerDocOpenCallback(handleOpen);
    server.registerDocSaveCallback(handleSave);
    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(allocator: std.mem.Allocator, context: *Lsp.Context, id: i32, position: lsp.types.Position) void {
    const line = position.line;
    if (context.state.?.test_results.get(line)) |test_result| {
        var message = std.ArrayList(u8).init(allocator);
        defer message.deinit();

        message.writer().print("Result: {any}\n\n", .{test_result.term.Exited}) catch unreachable;
        if (test_result.stdout.len > 0) message.writer().print("stdout:\n{s}\n\n", .{test_result.stdout}) catch unreachable;
        if (test_result.stderr.len > 0) message.writer().print("stderr:\n{s}\n\n", .{test_result.stderr}) catch unreachable;

        const response = lsp.types.Response.Hover.init(id, message.items);

        lsp.writeResponse(allocator, response) catch unreachable;
    }
}

fn handleOpen(allocator: std.mem.Allocator, context: *Lsp.Context) void {
    context.state = State.init(allocator);
    context.state.?.update(allocator, context.document) catch unreachable;
    sendDiagnostics(allocator, context.document.uri, context.state.?);
}

fn handleSave(allocator: std.mem.Allocator, context: *Lsp.Context) void {
    context.state.?.update(allocator, context.document) catch unreachable;
    sendDiagnostics(allocator, context.document.uri, context.state.?);
}

fn handleClose(allocator: std.mem.Allocator, context: *Lsp.Context) void {
    context.state.?.deinit(allocator);
}

fn sendDiagnostics(allocator: std.mem.Allocator, uri: []const u8, state: State) void {
    var it = state.test_results.iterator();
    var diagnostics = std.ArrayList(lsp.types.Diagnostic).init(allocator);
    defer diagnostics.deinit();
    while (it.next()) |result_obj| {
        const line = result_obj.key_ptr.*;
        const test_result = result_obj.value_ptr;
        const diagnostic = createDiagnostic(line, test_result.term.Exited == 0);
        diagnostics.append(diagnostic) catch unreachable;
    }

    const response = lsp.types.Notification.PublishDiagnostics{ .method = "textDocument/publishDiagnostics", .params = .{
        .uri = uri,
        .diagnostics = diagnostics.items,
    } };

    lsp.writeResponse(allocator, response) catch unreachable;
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
