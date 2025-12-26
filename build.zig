const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zig_glfw = b.dependency("zig_glfw", .{ .target = target, .optimize = optimize, .vulkan = true }).module("zig_glfw");
    const zig_opengl = b.dependency("zig_opengl", .{ .target = target, .optimize = optimize }).module("zig_opengl");
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

    const tiny_obj_loader_dep = b.dependency("tiny_obj_loader", .{});
    const tiny_obj_loader = b.addTranslateC(.{
        .root_source_file = tiny_obj_loader_dep.path("tinyobj_loader_c.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const cgltf_dep = b.dependency("cgltf", .{});
    const cgltf = b.addTranslateC(.{
        .root_source_file = cgltf_dep.path("cgltf.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const stb = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add(
            "c.h",
            \\#define STBI_ONLY_PNG
            \\#define STB_IMAGE_IMPLEMENTATION
            \\#include "stb_image.h"
            ,
        ),
        .target = target,
        .optimize = optimize,
    });
    stb.addIncludePath(b.dependency("stb", .{}).path("."));

    const cargo_cmd = b.addSystemCommand(&.{
        "cargo", "build", "--release",
    });

    const renderer = b.addLibrary(.{
        .name = "renderer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/render/Renderer.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "glfw", .module = zig_glfw },
                .{ .name = "gl", .module = zig_opengl },
                .{ .name = "numz", .module = numz },
                .{ .name = "ecs", .module = ecs },
                .{ .name = "vulkan", .module = vulkan_headers },
                .{ .name = "vma", .module = vma },
                .{ .name = "tiny_obj_loader", .module = tiny_obj_loader },
                .{ .name = "cgltf", .module = cgltf },
                .{ .name = "stb", .module = stb.createModule() },
            },
            .link_libcpp = true,
        }),
        .linkage = .dynamic,
    });

    renderer.root_module.linkSystemLibrary("vulkan", .{});

    b.installArtifact(renderer);

    const exe = b.addExecutable(.{
        .name = "PlanetaryZigma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "glfw", .module = zig_glfw },
                .{ .name = "gl", .module = zig_opengl },
                .{ .name = "numz", .module = numz },
                .{ .name = "ecs", .module = ecs },
                .{ .name = "vulkan", .module = vulkan_headers },
                .{ .name = "vma", .module = vma },
                .{ .name = "stb", .module = stb.createModule() },
                .{ .name = "Renderer", .module = renderer.root_module },
            },
            .link_libcpp = true,
        }),
    });

    exe.step.dependOn(&cargo_cmd.step);

    exe.root_module.linkSystemLibrary("unwind", .{});
    exe.root_module.linkSystemLibrary("openssl", .{});
    exe.root_module.addLibraryPath(b.path("target/release/"));
    exe.root_module.linkSystemLibrary("spacetime", .{});
    exe.root_module.linkSystemLibrary("vulkan", .{});

    renderer.addCSourceFile(.{
        .file = b.addWriteFiles().add("vma_impl.cpp",
            \\#define VMA_IMPLEMENTATION
            \\#include "vk_mem_alloc.h"
        ),
        .flags = &.{"-std=c++14"},
    });

    renderer.addCSourceFile(.{
        .file = b.addWriteFiles().add("tiny_obj_loader_impl.c",
            \\#define TINYOBJ_LOADER_C_IMPLEMENTATION
            \\#include "tinyobj_loader_c.h"
        ),
        .flags = &.{"-std=c99"},
    });

    renderer.addIncludePath(vma_dep.path("include/"));
    renderer.addIncludePath(vulkan_header_dep.path("include/"));
    renderer.addIncludePath(tiny_obj_loader_dep.path("."));
    renderer.addIncludePath(cgltf_dep.path("."));

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
