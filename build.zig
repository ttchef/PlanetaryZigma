const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const numz = b.dependency("numz", .{ .target = target, .optimize = optimize }).module("numz");
    const ecs = b.dependency("ecs", .{ .target = target, .optimize = optimize }).module("ecs");
    const vulkan_header_dep = b.dependency("vulkan_headers", .{});

    const vulkan_headers = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include "vulkan/vulkan.h"
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    vulkan_headers.addIncludePath(vulkan_header_dep.path("include/"));

    const vma_dep = b.dependency("vma", .{});
    const vma = b.addTranslateC(.{
        .root_source_file = vma_dep.path("include/vk_mem_alloc.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    vma.addIncludePath(vulkan_header_dep.path("include/"));

    const cgltf_dep = b.dependency("cgltf", .{});
    const cgltf = b.addTranslateC(.{
        .root_source_file = cgltf_dep.path("cgltf.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    cgltf.addIncludePath(cgltf_dep.path("."));

    const zphysics = b.dependency("zphysics", .{
        .use_double_precision = false,
        .enable_cross_platform_determinism = true,
    });

    const stb_dep = b.dependency("stb", .{});
    const stb = b.addTranslateC(.{
        .root_source_file = stb_dep.path("stb_image.h"),
        .target = target,
        .optimize = optimize,
    });
    stb.addIncludePath(b.dependency("stb", .{}).path("."));

    const sdl_dep = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        //.preferred_linkage = .static,
        //.strip = null,
        //.sanitize_c = null,
        //.pic = null,
        //.lto = null,
        //.emscripten_pthreads = false,
    });
    const sdl_header = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include <SDL3/SDL.h>
            \\#include <SDL3/SDL_vulkan.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    sdl_header.addIncludePath(sdl_dep.path("include/"));

    const cargo_cmd = b.addSystemCommand(&.{
        "cargo", "build", "--release",
    });

    const world_module = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .optimize = optimize,
        .target = target,
        .imports = &.{
            .{ .name = "numz", .module = numz },
            .{ .name = "ecs", .module = ecs },
        },
    });

    const system = b.addLibrary(.{
        .name = "system",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/System.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl", .module = sdl_header },
                .{ .name = "numz", .module = numz },
                .{ .name = "ecs", .module = ecs },
                .{ .name = "World", .module = world_module },
                // .{ .name = "cjolt", .module = cjolt },
            },
        }),
        .linkage = .dynamic,
    });
    system.root_module.addImport("zphysics", zphysics.module("root"));
    system.linkLibrary(zphysics.artifact("joltc"));
    system.root_module.linkSystemLibrary("SDL3", .{});
    b.installArtifact(system);

    const renderer = b.addLibrary(.{
        .name = "renderer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/render/Renderer.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl", .module = sdl_header },
                .{ .name = "numz", .module = numz },
                .{ .name = "ecs", .module = ecs },
                .{ .name = "vulkan", .module = vulkan_headers },
                .{ .name = "vma", .module = vma },
                .{ .name = "cgltf", .module = cgltf },
                .{ .name = "stb", .module = stb.createModule() },
                .{ .name = "World", .module = world_module },
            },
            .link_libcpp = true,
        }),
        .linkage = .dynamic,
    });

    renderer.root_module.linkSystemLibrary("vulkan", .{});
    renderer.root_module.linkSystemLibrary("SDL3", .{});

    b.installArtifact(renderer);

    const exe = b.addExecutable(.{
        .name = "PlanetaryZigma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl", .module = sdl_header },
                .{ .name = "numz", .module = numz },
                .{ .name = "ecs", .module = ecs },
                .{ .name = "vulkan", .module = vulkan_headers },
                .{ .name = "vma", .module = vma },
                .{ .name = "stb", .module = stb.createModule() },
                .{ .name = "Renderer", .module = renderer.root_module },
                .{ .name = "System", .module = system.root_module },
                .{ .name = "World", .module = world_module },
            },
            .link_libcpp = true,
        }),
    });
    exe.root_module.addImport("zphysics", zphysics.module("root"));
    exe.linkLibrary(zphysics.artifact("joltc"));
    exe.step.dependOn(&cargo_cmd.step);

    exe.root_module.linkSystemLibrary("unwind", .{});
    exe.root_module.linkSystemLibrary("openssl", .{});
    exe.root_module.addLibraryPath(b.path("target/release/"));
    exe.root_module.linkSystemLibrary("spacetime", .{});
    exe.root_module.linkSystemLibrary("vulkan", .{});
    exe.root_module.linkSystemLibrary("SDL3", .{});

    renderer.addCSourceFile(.{
        .file = b.addWriteFiles().add("vma_impl.cpp",
            \\#define VMA_IMPLEMENTATION
            \\#include "vk_mem_alloc.h"
        ),
        .flags = &.{"-std=c++14"},
    });

    renderer.addCSourceFile(.{
        .file = b.addWriteFiles().add("cgltf_impl.c",
            \\#define CGLTF_IMPLEMENTATION
            \\#include "cgltf.h"
        ),
        .flags = &.{"-std=c99"},
    });

    renderer.addCSourceFile(.{
        .file = b.addWriteFiles().add("stbi_impl.c",
            \\#define STB_IMAGE_IMPLEMENTATION
            \\#include "stb_image.h"
        ),
    });

    renderer.addIncludePath(vma_dep.path("include/"));
    renderer.addIncludePath(vulkan_header_dep.path("include/"));
    renderer.addIncludePath(cgltf_dep.path("."));
    renderer.addIncludePath(stb_dep.path("."));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    compileShaders(b) catch unreachable;
}

fn compileShaders(b: *std.Build) !void {
    try std.fs.cwd().makePath(b.fmt("{s}/{s}", .{ b.install_path, "shaders" }));
    const dir = try std.fs.cwd().openDir("assets/shaders/", .{ .iterate = true });
    var it = dir.iterate();

    while (try it.next()) |entry| {
        if (entry.kind != .file or std.mem.endsWith(u8, entry.name, ".glsl")) continue;
        const cmp_cmd = b.addSystemCommand(&.{
            "glslc",
            b.fmt("assets/shaders/{s}", .{entry.name}),
            "-o",
            b.fmt("zig-out/shaders/{s}.spv", .{entry.name}),
        });
        b.default_step.dependOn(&cmp_cmd.step);
    }
}
