const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const AssetServer = @import("shared").AssetServer;
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

//TODO: HARALD fix yes? <3 😼🔥
// pub const UpdateRenderer = *const fn (*@This(), f32) callconv(.c) void;
// pub const InitRenderer = *const fn (*@This(), *std.mem.Allocator, *AssetServer) callconv(.c) u32;
// pub const DeinitRenderer = *const fn (*@This(), *std.mem.Allocator) callconv(.c) void;
// // pub const ReloadRenderer = *const fn (*@This(), *std.mem.Allocator, .Config, bool) callconv(.c) void;
//
// export fn initSystems(self: *@This(), allocator: *std.mem.Allocator, asset_server: *AssetServer) u32 {
//
//     std.debug.print("hello", .{});
//     self.inner = try init(allocator, asset_server, )
//
//
//     self.renderer = Renderer.init(allocator.*, renderer_config.*) catch |err| return @intFromError(err);
//     initEcs(allocator.*, world, &self.renderer) catch |err| return @intFromError(err);
//     self.physics_system = Physics.init(allocator, world) catch |err| return @intFromError(err);
//     return 0;
// }
// export fn deinit(self: *@This(), allocator: *std.mem.Allocator) void {
//     var query = world.query(&.{ecs.Collider});
//     while (query.next()) |entry| {
//         var collider = entry.getPtr(ecs.Collider, world).?;
//         if (collider.shape == .mesh) {
//             collider.shape.mesh.vertices.deinit(allocator.*);
//             collider.shape.mesh.indices.deinit(allocator.*);
//         }
//     }
//
//     self.physics_system.deinit(allocator.*);
//     allocator.destroy(self.physics_system);
//     self.renderer.deinit(allocator.*);
//
//
// }
//
// export fn update(self: *@This(), delta_time: f32) u32 {
//     self.physics_system.update(world, &self.renderer, delta_time);
//     player.update(@ptrCast(world), @ptrCast(self.physics_system.physics_system), delta_time) catch @panic("\n\nMake a better panix xd,\n\n");
//
//     self.renderer.draw(world, delta_time) catch |err| return @intFromError(err);
//     return 0;
// }

pub fn init(allocator: std.mem.Allocator, asset_server: *AssetServer, window: *glfw.GLFWwindow) !@This() {
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
