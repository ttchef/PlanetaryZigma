const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.addModule("shared", .{
        .root_source_file = b.path("src/shared/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // const client_step = b.step("client", "Client step");
    const client_exe = client(b, target, optimize, shared);

    // const server_step = b.step("server", "Client step");
    const server_exe = server(b, target, optimize, shared);

    const run_step = b.step("run", "Run the app");
    const client_run_cmd = b.addRunArtifact(client_exe);
    const server_run_cmd = b.addRunArtifact(server_exe);
    run_step.dependOn(&client_run_cmd.step);
    run_step.dependOn(&server_run_cmd.step);
    client_run_cmd.step.dependOn(b.getInstallStep());
    server_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        client_run_cmd.addArgs(args);
        server_run_cmd.addArgs(args);
    }
}

pub fn client(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shared: *std.Build.Module) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
            },
        }),
    });
    b.installArtifact(exe);

    return exe;
}

pub fn server(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shared: *std.Build.Module) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
            },
        }),
    });
    b.installArtifact(exe);

    return exe;
}
