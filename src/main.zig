const std = @import("std");
const lsp = @import("lsp");

const State = @import("analysis.zig").State;
const Lsp = lsp.Lsp(State);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub fn main() !u8 {
    const server_data = lsp.types.ServerData{
        .capabilities = .{
            .hoverProvider = true,
        },
        .serverInfo = .{
            .name = "test-ls",
            .version = "0.1.1",
        },
    };
    var server = Lsp.init(allocator, server_data);
    defer server.deinit();

    server.registerDocOpenCallback(handleOpen);
    server.registerDocSaveCallback(handleSave);
    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(arena: std.mem.Allocator, context: *Lsp.Context, position: lsp.types.Position) ?[]const u8 {
    const line = position.line;
    if (context.state.?.test_results.get(line)) |test_result| {
        var message = std.ArrayList(u8).init(arena);

        message.writer().print("Result: {any}\n\n", .{test_result.status}) catch unreachable;
        if (test_result.output.len > 0) message.writer().print("output:\n{s}\n\n", .{test_result.output}) catch unreachable;

        return message.items;
    }
    return null;
}

fn handleOpen(arena: std.mem.Allocator, context: *Lsp.Context) void {
    context.state = State.init(allocator);
    context.state.?.update(allocator, context.document) catch unreachable;
    sendDiagnostics(arena, context.document.uri, context.state.?);
}

fn handleSave(arena: std.mem.Allocator, context: *Lsp.Context) void {
    context.state.?.update(allocator, context.document) catch unreachable;
    sendDiagnostics(arena, context.document.uri, context.state.?);
}

fn handleClose(_: std.mem.Allocator, context: *Lsp.Context) void {
    context.state.?.deinit(allocator);
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

    lsp.writeResponse(arena, response) catch unreachable;
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
