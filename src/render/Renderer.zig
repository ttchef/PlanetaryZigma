const std = @import("std");
const vma = @import("vma");
pub const vk = @import("Vulkan/vulkan.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");
const Image = @import("Vulkan/Image.zig");

instance: *vk.Instance,
debug_messenger: *vk.DebugMessenger,
surface: *vk.Surface,
physical_device: vk.PhysicalDevice,
device: *vk.Device,
swapchain: Swapchain,
command_pool: *vk.CommandPool,
vulkan_mem_alloc: vma.VmaAllocator,
draw_image: Image,
draw_extent: vk.c.VkExtent2D,

pub const Config = struct { instance: struct {
    extensions: ?[]const [*:0]const u8 = null,
    layers: ?[]const [*:0]const u8 = null,
    debug_config: vk.DebugMessenger.Config = .{},
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
    const debug_messenger: *vk.DebugMessenger = try .init(instance, config.instance.debug_config);
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

    // TODO: Initialize VMA properly
    var vma_info: vma.VmaAllocatorCreateInfo = .{
        .physicalDevice = @ptrCast(physical_device.ptr),
        .device = @ptrCast(device),
        .instance = @ptrCast(instance),
        .flags = vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };
    var vulkan_mem_alloc: vma.VmaAllocator = undefined;
    try vk.check(vma.vmaCreateAllocator(&vma_info, &vulkan_mem_alloc));

    var draw_image: Image = .{
        .imageFormat = vk.c.VK_FORMAT_R16G16B16A16_SFLOAT,
        .imageExtent = .{
            .width = config.swapchain.width,
            .height = config.swapchain.heigth,
            .depth = 1,
        },
    };
    const draw_image_usages_flags: vk.c.VkImageUsageFlags =
        vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
        vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
        vk.c.VK_IMAGE_USAGE_STORAGE_BIT |
        vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .command_pool = command_pool,
        .vulkan_mem_alloc = vulkan_mem_alloc,
    };
}

pub fn draw(self: *@This()) !void {
    var image_index: u32 = undefined;
    const current_frame = self.swapchain.frames[self.swapchain.current_frame_inflight % self.swapchain.frames.len];
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

    var submit_info: vk.c.VkSubmitInfo2 = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_frame.swapchain_semaphore,
            .stageMask = vk.c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
            .value = 1,
        },
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_frame.render_done_semaphore,
            .stageMask = vk.c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .value = 1,
        },
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = cmd_buffer,
        },
    };

    try vk.check(vk.c.vkQueueSubmit2(self.device.getQueue(self.physical_device.queue_family_index).toC(), 1, &submit_info, current_frame.render_fence));

    var present_info: vk.c.VkPresentInfoKHR = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.swapchain.swapchain,
        .swapchainCount = 1,
        .pWaitSemaphores = &current_frame.render_done_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };

    try vk.check(vk.c.vkQueuePresentKHR(self.device.getQueue(self.physical_device.queue_family_index).toC(), &present_info));

    self.swapchain.current_frame_inflight += 1;
    //https://vkguide.dev/docs/new_chapter_2/vulkan_new_rendering/
    //TODO: VMA.
}

pub fn deinit(self: @This()) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.toC());
    self.swapchain.deinit(self.device, self.command_pool);
    self.command_pool.deinit(self.device);
    vma.vmaDestroyAllocator(self.vulkan_mem_alloc);
    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
}
