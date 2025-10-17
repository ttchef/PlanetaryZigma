pub const vk = @import("Vulkan/vulkan.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");

instance: *vk.Instance,
debug_messenger: *vk.DebugMessenger,
surface: *vk.Surface,
physical_device: *vk.PhysicalDevice,
device: *vk.Device,
swapchain: Swapchain,

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
    const swapchain: Swapchain = try .init(physical_device, device, surface, config.swapchain.width, config.swapchain.heigth);
    // TODO
    // Command Pool
    // Swapchain Images
    // Desctiptors, Pools
    // Shaders
    // Pipeline

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
    };
}

pub fn deinit(self: @This()) void {
    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
}
