const std = @import("std");
const builtin = @import("builtin");

inner: Inner,

const Metal = @import("Renderer/Metal.zig");
const Vulkan = @import("Renderer/Vulkan.zig");

pub const Inner = switch (builtin.os.tag) {
    .macos => Metal,
    else => Vulkan,
};

pub fn init(allocator: std.mem.Allocator) !@This() {
    return .{ .inner = try .init(allocator) };
}

pub fn deinit(self: *@This()) void {
    self.inner.deinit();
}

pub fn update(self: *@This()) !void {
    try self.inner.update();
}
