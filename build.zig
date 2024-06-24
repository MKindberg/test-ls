const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "test-ls",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lsp_server = b.dependency("lsp-server", .{
        .target = target,
        .optimize = optimize,
    });
    const lsp = lsp_server.module("lsp");
    exe.root_module.addImport("lsp", lsp);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const registry_generator = b.addExecutable(.{
        .name = "generate_registry",
        .root_source_file = b.path("tools/mason_registry.zig"),
        .target = b.host,
    });
    const registry_step = b.step("gen_registry", "Generate mason.nvim registry");
    const registry_generation = b.addRunArtifact(registry_generator);
    registry_step.dependOn(&registry_generation.step);
}
