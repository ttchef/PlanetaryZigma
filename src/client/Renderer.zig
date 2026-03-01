const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");

inner: Inner,

const Metal = @import("Renderer/Metal.zig");
const Vulkan = @import("Renderer/Vulkan.zig");

pub const Inner = switch (builtin.os.tag) {
    .macos => Metal,
    else => Vulkan,
};

pub fn init(allocator: std.mem.Allocator, window: *glfw.GLFWwindow) !@This() {
    switch (builtin.os.tag) {
        .macos => return error.MacOsNotImplemented,
        else => {
            var extension_count: u32 = undefined;
            const glfw_extensions: [*][*:0]const u8 = @ptrCast(glfw.glfwGetRequiredInstanceExtensions(&extension_count));
            var extensions: [8][*:0]const u8 = undefined;
            @memcpy(extensions[0..extension_count], glfw_extensions[0..extension_count]);
            extensions[extension_count] = Vulkan.c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
            return .{ .inner = try .init(allocator, .{ .surface = .{
                .data = window,
                .init = createVulkanSurface,
            }, .instance = .{
                .extensions = extensions[0 .. extension_count + 1],
            } }) };
        },
    }
}

pub fn deinit(self: *@This()) void {
    self.inner.deinit();
}

pub fn update(self: *@This()) !void {
    try self.inner.update();
}

pub fn createVulkanSurface(vk_instance: Vulkan.c.VkInstance, window: *anyopaque) !Vulkan.c.VkSurfaceKHR {
    var surface: Vulkan.c.VkSurfaceKHR = undefined;
    try Vulkan.check(glfw.glfwCreateWindowSurface(@ptrCast(vk_instance), @ptrCast(window), null, @ptrCast(&surface)));
    return surface;
}
