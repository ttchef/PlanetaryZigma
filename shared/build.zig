const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const numz = b.dependency("numz", .{ .target = target, .optimize = optimize }).module("numz");
    const ecz = b.dependency("ecz", .{ .target = target, .optimize = optimize }).module("ecz");

    _ = b.addModule("shared", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "numz", .module = numz },
            .{ .name = "ecz", .module = ecz },
        },
    });
}
