const std = @import("std");
const builtin = @import("builtin");
const shared = @import("shared");
const Info = shared.Info;
const yes = @import("yes");
const AssetServer = shared.AssetServer;

inner: Inner,

const Metal = @import("Renderer/Metal.zig");
const Vulkan = @import("Renderer/Vulkan.zig");

pub const Inner = switch (builtin.os.tag) {
    .macos => *Metal,
    else => *Vulkan,
};

const YesSurfaceCreateUserData = struct {
    platform: yes.Platform,
    window: *yes.Platform.Window,
};

pub fn init(allocator: std.mem.Allocator, asset_server: *AssetServer, platform: yes.Platform, window: *yes.Platform.Window) !@This() {
    return switch (builtin.os.tag) {
        .macos => .{ .inner = Metal.init(allocator, platform, window) },
        else => initVulkan(allocator, asset_server, platform, window),
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.inner.deinit(allocator);
    switch (builtin.os.tag) {
        .macos => self.inner.deinit(),
        else => {
            allocator.destroy(self.inner);
        },
    }
}

pub fn update(self: *@This(), info: Info) !void {
    try self.inner.update(info);
}

pub fn resize(self: *@This(), allocator: std.mem.Allocator, window: *yes.Platform.Window) !void {
    try self.inner.resize(allocator, window.size.width, window.size.height);
}

pub fn initVulkan(allocator: std.mem.Allocator, asset_server: *AssetServer, platform: yes.Platform, window: *yes.Platform.Window) !@This() {
    const extensions: []const [*:0]const u8 = switch (builtin.os.tag) {
        .windows => &.{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
            Vulkan.c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
        },
        else => &.{
            "VK_KHR_xlib_surface",
            Vulkan.c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
            Vulkan.c.VK_KHR_SURFACE_EXTENSION_NAME,
            Vulkan.c.VK_KHR_DISPLAY_EXTENSION_NAME,
        },
    };

    var yes_surface_create_user_data: YesSurfaceCreateUserData = .{ .platform = platform, .window = window };

    const vulkan_renderer: *Vulkan = try .init(allocator, asset_server, .{
        .surface = .{
            .data = @ptrCast(@alignCast(&yes_surface_create_user_data)),
            .init = @ptrCast(&createVulkanSurface),
        },
        .instance = .{
            .extensions = extensions,
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
            .width = window.size.width,
            .heigth = window.size.height,
        },
    });
    return .{ .inner = vulkan_renderer };
}

fn createVulkanSurface(instance: *yes.vulkan.Instance, user_data: *const YesSurfaceCreateUserData) !*yes.vulkan.Surface {
    return yes.vulkan.Surface.create(user_data.platform, user_data.window, instance, null, @ptrCast(&Vulkan.c.vkGetInstanceProcAddr));
}
