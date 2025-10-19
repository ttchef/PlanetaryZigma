const std = @import("std");
pub const vk = @import("Vulkan/vulkan.zig");

instance: *vk.Instance,
debug_messenger: *vk.DebugMessenger,
surface: *vk.Surface,
physical_device: vk.PhysicalDevice,
device: *vk.Device,
swapchain: vk.Swapchain,
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
    const physical_device: vk.PhysicalDevice = try .find(instance, surface);
    const device: *vk.Device = try .init(physical_device, config.device.extensions);
    const command_pool: *vk.CommandPool = try .init(device, physical_device.queue_family_index);
    const swapchain: vk.Swapchain = try .init(physical_device, device, command_pool, surface, config.swapchain.width, config.swapchain.heigth);

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
    var image_index: u32 = undefined;
    const current_frame = self.swapchain.frames[self.swapchain.current_frame_inflight];
    try vk.check(vk.c.vkWaitForFences(self.device.toC(), 1, &current_frame.render_fence, 1, 1000000000));
    try vk.check(vk.c.vkResetFences(self.device.toC(), 1, &current_frame.render_fence));
    try vk.check(vk.c.vkAcquireNextImageKHR(
        self.device.toC(),
        self.swapchain.swapchain,
        1000000000,
        current_frame.swapchain_semaphore,
        null,
        &image_index,
    ));

    const cmd_buffer = current_frame.command_buffer;
    try vk.check(vk.c.vkResetCommandBuffer(cmd_buffer, 0));
    var cmd_begin_info: vk.c.VkCommandBufferBeginInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.check(vk.c.vkBeginCommandBuffer(cmd_buffer, &cmd_begin_info));

    try vk.imageMemBarrier(cmd_buffer, self.swapchain.vk_images[image_index], self.swapchain.format, vk.c.VK_IMAGE_LAYOUT_UNDEFINED, vk.c.VK_IMAGE_LAYOUT_GENERAL);
    var clear_value: vk.c.VkClearColorValue = .{ .float32 = .{ 0.0, 0.0, std.math.sin(@as(f32, @floatFromInt(self.swapchain.current_frame_inflight)) / 120.0), 1.0 } };

    var clear_range: vk.c.VkImageSubresourceRange = .{
        .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        .baseMipLevel = 0,
        .levelCount = vk.c.VK_REMAINING_MIP_LEVELS,
        .baseArrayLayer = 0,
        .layerCount = vk.c.VK_REMAINING_ARRAY_LAYERS,
    };

    vk.c.vkCmdClearColorImage(cmd_buffer, self.swapchain.vk_images[image_index], vk.c.VK_IMAGE_LAYOUT_GENERAL, &clear_value, 1, &clear_range);

    try vk.imageMemBarrier(cmd_buffer, self.swapchain.vk_images[image_index], self.swapchain.format, vk.c.VK_IMAGE_LAYOUT_GENERAL, vk.c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    try vk.check(vk.c.vkEndCommandBuffer(cmd_buffer));

    //TODO https://vkguide.dev/docs/new_chapter_1/vulkan_mainloop_code/
    // VkSemaphoreSubmitInfo
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
