const std = @import("std");
pub const vk = @import("vulkan");

pub fn init(allocator: std.mem.Allocator) !@This() {
    _ = allocator;
    return .{};
}

pub fn deinit(self: *@This()) void {
    _ = self;
}

pub fn update(self: *@This()) !void {
    _ = self;
}
