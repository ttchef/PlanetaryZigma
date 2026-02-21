const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("shared", .{
        .root_source_file = b.path("src/shared/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    buildClient(b, target, optimize);
    buildServer(b, target, optimize);
}

// TODO(ernesto): HOT RELOADING
pub fn buildClient(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shared = b.modules.get("shared").?;

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

    const run_step = b.step("run-client", "Run the client");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}

pub fn buildServer(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shared = b.modules.get("shared").?;
    const zphysics = b.dependency("zphysics", .{
        .use_double_precision = false,
        .enable_cross_platform_determinism = true,
    });

    //NOTE: hot reloading.
    const system = b.addLibrary(.{
        .name = "system",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server/System.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                .{ .name = "zphy", .module = zphysics.module("root") },
            },
        }),
        .linkage = .dynamic,
    });
    system.root_module.linkLibrary(zphysics.artifact("joltc"));

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                .{ .name = "System", .module = system.root_module },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run-server", "Run the server");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}
