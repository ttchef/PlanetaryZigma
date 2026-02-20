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

// TODO(ernesto): HOT RELOADING
pub fn client(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, shared: *std.Build.Module) *std.Build.Step.Compile {
    const glfw_headers = b.dependency("glfw_headers", .{});
    const glfw_translate_c = b.addTranslateC(.{
        .root_source_file = glfw_headers.path("include/GLFW/glfw3.h"),
        // b.addWriteFiles().add("c.h",
        // \\#define GLFW_INCLUDE_NONE
        // \\#include <GLFW/glfw3.h>
        // ),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                .{ .name = "glfw", .module = glfw_translate_c.createModule() },
            },
        }),
    });

    exe.root_module.linkLibrary(b.dependency("glfw", .{ .target = target, .optimize = optimize }).artifact("glfw3"));

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
