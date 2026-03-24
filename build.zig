const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const numz = b.dependency("numz", .{ .target = target, .optimize = optimize }).module("numz");
    const ec = b.dependency("ecs", .{ .target = target, .optimize = optimize }).module("ecs");

    _ = b.addModule("shared", .{
        .root_source_file = b.path("src/shared/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ecs", .module = ec },
            .{ .name = "numz", .module = numz },
        },
    });
    const io = b.graph.io;
    std.Io.Dir.cwd().deleteTree(io, "zig-out/lib/") catch unreachable;

    buildClient(b, target, optimize);
    buildServer(b, target, optimize);
}

pub fn buildClient(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shared = b.modules.get("shared").?;

    const yes = b.dependency("yes", .{ .target = target, .optimize = optimize, .xlib = true }).module("yes");

    const wasm_runtime = b.dependency("wasm_runtime", .{ .target = target, .optimize = optimize }).module("wasm_runtime");
    const io = b.graph.io;
    const time = std.Io.Timestamp.now(io, .real);
    const system = b.addLibrary(.{
        .name = b.fmt("system_client_{d}", .{time}),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client/system.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                .{ .name = "yes", .module = yes },
            },
            .link_libc = true,
        }),
        .linkage = .dynamic,
    });

    const exe = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                .{ .name = "system", .module = system.root_module },
                .{ .name = "yes", .module = yes },
                .{ .name = "wasm_runtime", .module = wasm_runtime },
            },
            .link_libc = true,
        }),
    });

    if (target.result.os.tag.isDarwin()) {
        const objc = b.lazyDependency("zig_objc", .{
            .target = target,
            .optimize = optimize,
        }).?.module("objc");
        exe.root_module.addImport("objc", objc);
    } else {
        const vulkandeps = b.dependency("vulkan_headers", .{});
        const vmadep = b.dependency("vma", .{});

        const vulkan_c = b.addTranslateC(.{
            .root_source_file = b.addWriteFiles().add("vma_vulkan.h",
                \\#include <vulkan/vulkan.h>
                \\#include <vk_mem_alloc.h>
            ),
            .target = target,
            .optimize = optimize,
        });
        vulkan_c.addIncludePath(vulkandeps.path("include/"));
        vulkan_c.addIncludePath(vmadep.path("include/"));

        const vulkan = vulkan_c.createModule();
        vulkan.link_libcpp = true;
        for (vulkan_c.include_dirs.items) |include_dir| vulkan.addIncludePath(include_dir.path);

        vulkan.addCSourceFile(.{
            .file = b.addWriteFiles().add("vma_impl.cpp",
                \\#define VMA_STATIC_VULKAN_FUNCTIONS 1
                \\#define VMA_DYNAMIC_VULKAN_FUNCTIONS 0
                \\#define VMA_IMPLEMENTATION
                \\#include <vk_mem_alloc.h>
            ),
            .flags = &.{"-std=c++17"},
        });

        const shaderc_dep = b.dependency("shaderc", .{});
        const shaderc_c = b.addTranslateC(.{
            .root_source_file = shaderc_dep.path("libshaderc/include/shaderc/shaderc.h"),
            .target = target,
            .optimize = optimize,
        });
        const shaderc = shaderc_c.createModule();
        system.root_module.addImport("shaderc", shaderc);

        system.root_module.addImport("vulkan", vulkan);
        exe.root_module.linkSystemLibrary("vulkan", .{});
        exe.root_module.linkSystemLibrary("shaderc_shared", .{});
        exe.root_module.link_libcpp = true;
    }

    if (target.result.os.tag == .macos) {
        exe.root_module.linkFramework("Cocoa", .{});
        exe.root_module.linkFramework("QuartzCore", .{});
        exe.root_module.linkFramework("Metal", .{});
        exe.root_module.linkFramework("CoreGraphics", .{});
        exe.root_module.linkFramework("ImageIO", .{});
        exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
        exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });

        exe.root_module.linkSystemLibrary("shaderc_shared", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-c", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-core", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-cpp", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-glsl", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-hlsl", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-msl", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-reflect", .{});
        exe.root_module.linkSystemLibrary("spirv-cross-util", .{});
        exe.root_module.link_libcpp = true;
    }

    b.installArtifact(system);
    b.installArtifact(exe);

    const run_step = b.step("run-client", "Run the client");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}

pub fn buildServer(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shared = b.modules.get("shared").?;
    // const zphysics = b.dependency("zphysics", .{
    //     .use_double_precision = false,
    //     .enable_cross_platform_determinism = true,
    // });

    const io = b.graph.io;
    const time = std.Io.Timestamp.now(io, .real);
    const system = b.addLibrary(.{
        .name = b.fmt("system_server_{d}", .{time}),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server/system.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                // .{ .name = "zphy", .module = zphysics.module("root") },
            },
            .link_libc = true,
        }),
        .linkage = .dynamic,
    });

    b.installArtifact(system);
    // system.root_module.linkLibrary(zphysics.artifact("joltc"));

    const exe = b.addExecutable(.{
        .name = "server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/server/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "shared", .module = shared },
                .{ .name = "system", .module = system.root_module },
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
