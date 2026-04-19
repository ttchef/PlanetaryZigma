const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const numz = b.dependency("numz", .{ .target = target, .optimize = optimize }).module("numz");
    const ecz = b.dependency("ecz", .{ .target = target, .optimize = optimize }).module("ecz");

    const shared = b.addModule("shared", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "numz", .module = numz },
            .{ .name = "ecz", .module = ecz },
        },
    });

    const tests = b.addTest(.{ .root_module = shared });
    const test_step = b.step("test", "Run shared tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
