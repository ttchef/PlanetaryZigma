const std = @import("std");
pub const vk = @import("Vulkan/vulkan.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");

instance: *vk.Instance,
debug_messenger: *vk.DebugMessenger,
surface: *vk.Surface,
physical_device: *vk.PhysicalDevice,
device: *vk.Device,
swapchain: Swapchain,
command_pool: *vk.CommandPool,

pub const Config = struct { instance: struct {
    extensions: ?[]const [*:0]const u8 = null,
    layers: ?[]const [*:0]const u8 = null,
} = .{}, device: struct {
    extensions: ?[]const [*:0]const u8 = null,
} = .{}, surface: struct {
    data: ?*anyopaque = null,
    init: ?*const fn (*vk.Instance, *anyopaque) anyerror!*anyopaque = null,
} = .{}, swapchain: struct {
    width: u32 = 0,
    heigth: u32 = 0,
} };

pub fn init(config: Config) !@This() {
    const instance: *vk.Instance = try .init(config.instance.extensions, config.instance.layers);
    const debug_messenger: *vk.DebugMessenger = try .init(instance, .{});
    const surface: *vk.Surface = if (config.surface.init != null and config.surface.data != null) @ptrCast(try config.surface.init.?(instance, config.surface.data.?)) else try vk.Surface.init(instance);
    const physical_device: *vk.PhysicalDevice, const queue_family_index: u32 = try vk.PhysicalDevice.find(instance, surface);
    const device: *vk.Device = try .init(physical_device, queue_family_index, config.device.extensions);
    const command_pool: *vk.CommandPool = try .init(device, queue_family_index);
    const swapchain: Swapchain = try .init(physical_device, device, command_pool, surface, config.swapchain.width, config.swapchain.heigth);

    // TODO
    // Desctiptors, Pools
    // Shaders
    // Pipeline

    std.debug.print("Address {*}\n", .{instance});

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .command_pool = command_pool,
    };
}

pub fn draw(self: @This()) !void {
    _ = self;
    // const image_index = vk.c.vkAcquireNextImageKHR(self.device.toC(), self.swapchain.swapchain, 1000000000, self.)
    // vk.check(vk.c.vkWaitForFences(self.device.toC(), 1, pFences: [*c]const ?*struct_VkFence_T, waitAll: u32, timeout: u64))
    // VK_CHECK(vkWaitForFences(_device, 1, &get_current_frame()._renderFence, true, 1000000000));
    // VK_CHECK(vkResetFences(_device, 1, &get_current_frame()._renderFence));
}

pub fn deinit(self: @This()) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.toC());
    self.swapchain.deinit(self.device, self.command_pool);
    self.command_pool.deinit(self.device);
    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
}
