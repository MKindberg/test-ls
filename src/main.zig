const std = @import("std");
const lsp = @import("lsp");
const builtin = @import("builtin");

const State = @import("analysis.zig").State;
const Lsp = lsp.Lsp(State);

pub const std_options = .{ .log_level = if (builtin.mode == .Debug) .debug else .info, .logFn = lsp.log };

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var server: Lsp = undefined;
const allocator = gpa.allocator();

pub fn main() !u8 {
    const server_data = lsp.types.ServerData{
        .serverInfo = .{
            .name = "test-ls",
            .version = "0.1.1",
        },
    };
    server = Lsp.init(allocator, server_data);
    defer server.deinit();

    server.registerDocOpenCallback(handleOpen);
    server.registerDocSaveCallback(handleSave);
    server.registerHoverCallback(handleHover);
    server.registerDocCloseCallback(handleClose);

    return server.start();
}

fn handleHover(p: Lsp.HoverParameters) ?[]const u8 {
    const line = p.position.line;
    if (p.context.state.?.test_results.get(line)) |test_result| {
        var message = std.ArrayList(u8).init(p.arena);

        message.writer().print("Result: {any}\n\n", .{if (test_result.status) "Passed" else "Failed"}) catch unreachable;
        if (test_result.output.len > 0) message.writer().print("output:\n{s}\n\n", .{test_result.output}) catch unreachable;

        return message.items;
    }
    return null;
}

fn handleOpen(p: Lsp.OpenDocumentParameters) void {
    p.context.state = State.init(allocator);
    p.context.state.?.update(allocator, p.context.document) catch unreachable;
    sendDiagnostics(p.arena, p.context.document.uri, p.context.state.?);
}

fn handleSave(p: Lsp.SaveDocumentParameters) void {
    p.context.state.?.update(allocator, p.context.document) catch unreachable;
    sendDiagnostics(p.arena, p.context.document.uri, p.context.state.?);
}

fn handleClose(p: Lsp.CloseDocumentParameters) void {
    p.context.state.?.deinit(allocator);
}

fn sendDiagnostics(arena: std.mem.Allocator, uri: []const u8, state: State) void {
    var it = state.test_results.iterator();
    var diagnostics = std.ArrayList(lsp.types.Diagnostic).init(arena);
    defer diagnostics.deinit();
    while (it.next()) |result_obj| {
        const line = result_obj.key_ptr.*;
        const test_result = result_obj.value_ptr;
        const diagnostic = createDiagnostic(line, test_result.status);
        diagnostics.append(diagnostic) catch unreachable;
    }

    const response = lsp.types.Notification.PublishDiagnostics{ .method = "textDocument/publishDiagnostics", .params = .{
        .uri = uri,
        .diagnostics = diagnostics.items,
    } };

    server.writeResponse(arena, response) catch unreachable;
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
