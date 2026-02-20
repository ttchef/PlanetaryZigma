const std = @import("std");

// TODO(ernesto): We should generate docs from our code. See how Zig std does it.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // TODO(ernesto): Shared should be separated into it's own compilation unit so we can hot reload.
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
    const platform_api = b.addTranslateC(.{
        .root_source_file = b.path("src/client/platform_api.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const exe = switch (target.result.os.tag) {
        .linux => exe_block: {
            const wayland = b.option(bool, "wayland", "Use wayland windowing system") orelse false;

            const exe = b.addExecutable(.{
                .name = if (wayland) "client-wayland" else "client-xorg",
                .root_module = b.createModule(.{
                    .root_source_file = b.path(if (wayland) "src/client/wayland.zig" else "src/client/xorg.zig"),
                    .target = target,
                    .optimize = optimize,
                    .imports = &.{
                        .{ .name = "shared", .module = shared },
                    },
                    .link_libc = true,
                }),
            });
            // NOTE(ernesto): Should we move to our own headers so we don't need libc?
            exe.root_module.linkSystemLibrary("vulkan", .{});
            exe.root_module.addImport("platform_api", platform_api);
            if (wayland) {
                const vulkan_and_stuff = b.addTranslateC(.{
                    .root_source_file = b.addWriteFiles().add("c.h",
                        \\#include <wayland-client.h>
                        \\#include <xdg-shell.h>
                        \\#include <xkbcommon/xkbcommon.h>
                        \\#include <vulkan/vulkan.h>
                        \\#include <vulkan/vulkan_wayland.h>
                    ),
                    .target = target,
                    .optimize = optimize,
                }).createModule();
                exe.root_module.addImport("vulkanAndStuff", vulkan_and_stuff);
                exe.root_module.linkSystemLibrary("wayland-client", .{});
                exe.root_module.linkSystemLibrary("xkbcommon", .{});
            } else {
                const xcb_and_stuff = b.addTranslateC(.{
                    .root_source_file = b.addWriteFiles().add("c.h",
                        \\#include <xcb/xcb.h>
                        \\#include <xcb/xcb_keysyms.h>
                        \\#include <vulkan/vulkan.h>
                        \\#include <vulkan/vulkan_wayland.h>
                        \\#include <xcb/xcb_icccm.h>
                    ),
                    .target = target,
                    .optimize = optimize,
                }).createModule();
                exe.root_module.addImport("xcbAndStuff", xcb_and_stuff);
                exe.root_module.linkSystemLibrary("xcb", .{});
                exe.root_module.linkSystemLibrary("xcb-keysyms", .{});
                exe.root_module.linkSystemLibrary("xcb-icccm", .{});
            }
            b.installArtifact(exe);
            break :exe_block exe;
        },
        else => {
            std.debug.panic("Compilation not implemented for target OS: {any}\n", .{target.result.os.tag});
        },
    };

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
