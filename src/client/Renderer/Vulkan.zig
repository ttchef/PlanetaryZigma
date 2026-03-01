const std = @import("std");
pub const c = @import("vulkan");
pub const Func = @import("Vulkan/utils.zig").Func;
const Instance = @import("Vulkan/Instance.zig");
const DebugMessenger = @import("Vulkan/DebugMessenger.zig");
pub const check = @import("Vulkan/utils.zig").check;

pub const Surface = struct {
    handle: c.VkSurfaceKHR,

    pub fn deinit(self: @This(), instance: Instance) void {
        c.vkDestroySurfaceKHR(instance.handle, self.handle, null);
    }
};

instance: Instance,
debug_messenger: DebugMessenger,
surface: Surface,

pub const Config = struct {
    instance: struct {
        extensions: []const [*:0]const u8,
    },
    surface: struct {
        data: ?*anyopaque = null,
        init: ?*const fn (c.VkInstance, *anyopaque) anyerror!c.VkSurfaceKHR = null,
    } = .{},
};

pub fn init(
    allocator: std.mem.Allocator,
    config: Config,
) !@This() {
    const instance: Instance = try .init(config.instance.extensions);
    const debug_messenger: DebugMessenger = try .init(instance, .{
        .severities = if (try std.process.Environ.contains(.empty, allocator, "RENDERDOC_CAPFILE")) .{} else .{
            .warning = true,
            .verbose = true,
            .@"error" = true,
            .info = true,
        },
    });
    const surface: Surface = if (config.surface.init != null and config.surface.data != null) .{
        .handle = @ptrCast(try config.surface.init.?(instance.handle, config.surface.data.?)),
    } else return error.configSurface;

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
    };
    //     c.VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
    // c.VK_EXT_DESCRIPTOR_BUFFER_EXTENSION_NAME,
    // c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
}

pub fn deinit(self: *@This()) void {
    _ = self;
}

pub fn update(self: *@This()) !void {
    _ = self;
}
