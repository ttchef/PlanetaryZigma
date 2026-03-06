const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const AssestServer = @import("shared").AssetServer;
inner: *Inner,

const Metal = @import("Renderer/Metal.zig");
const Vulkan = @import("Renderer/Vulkan.zig");

pub const Inner = switch (builtin.os.tag) {
    .macos => Metal,
    else => Vulkan,
};

const GlfwUserData = struct {
    renderer: *Vulkan,
    allocator: std.mem.Allocator,
};

pub fn init(allocator: std.mem.Allocator, asset_server: *AssestServer, window: *glfw.GLFWwindow) !@This() {
    var width: c_int = undefined;
    var heigth: c_int = undefined;
    glfw.glfwGetWindowSize(window, &width, &heigth);
    switch (builtin.os.tag) {
        .macos => return error.MacOsNotImplemented,
        else => {
            var extension_count: u32 = undefined;
            const glfw_extensions: [*][*:0]const u8 = @ptrCast(glfw.glfwGetRequiredInstanceExtensions(&extension_count));
            var extensions: [8][*:0]const u8 = undefined;
            @memcpy(extensions[0..extension_count], glfw_extensions[0..extension_count]);
            extensions[extension_count] = Vulkan.c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
            const vulkan_render = try allocator.create(Vulkan);
            vulkan_render.* = try .init(allocator, asset_server, .{
                .surface = .{
                    .data = window,
                    .init = createVulkanSurface,
                },
                .instance = .{
                    .extensions = extensions[0 .. extension_count + 1],
                    .layers = &.{
                        "VK_LAYER_KHRONOS_validation",
                    },
                },
                .device = .{
                    .extensions = &.{
                        Vulkan.c.VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
                        Vulkan.c.VK_EXT_EXTENDED_DYNAMIC_STATE_EXTENSION_NAME,
                        Vulkan.c.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
                        Vulkan.c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
                        Vulkan.c.VK_EXT_SHADER_OBJECT_EXTENSION_NAME,
                    },
                },
                .swapchain = .{
                    .width = @intCast(width),
                    .heigth = @intCast(heigth),
                },
            });
            const user_data = try allocator.create(GlfwUserData);
            user_data.* = .{
                .renderer = vulkan_render,
                .allocator = allocator,
            };
            glfw.glfwSetWindowUserPointer(window, user_data);
            _ = glfw.glfwSetWindowSizeCallback(window, recreateVulkanSwapchain);
            return .{
                .inner = vulkan_render,
            };
        },
    }
}

pub fn deinit(self: *@This()) void {
    self.inner.deinit();
}

pub fn update(self: *@This()) !void {
    try self.inner.update();
}

pub fn recreateVulkanSwapchain(window: ?*glfw.GLFWwindow, width: c_int, heigth: c_int) callconv(.c) void {
    std.debug.print("-------RECREATE----- {d} \n", .{1});
    const user_data: *GlfwUserData = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(window)));
    user_data.renderer.reCreateSwapchain(user_data.allocator, @intCast(width), @intCast(heigth)) catch unreachable;
}

pub fn createVulkanSurface(vk_instance: Vulkan.c.VkInstance, window: *anyopaque) !Vulkan.c.VkSurfaceKHR {
    var surface: Vulkan.c.VkSurfaceKHR = undefined;
    try Vulkan.check(glfw.glfwCreateWindowSurface(@ptrCast(vk_instance), @ptrCast(window), null, @ptrCast(&surface)));
    return surface;
}
