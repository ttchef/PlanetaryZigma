const std = @import("std");
const vk = @import("vulkan.zig");
const check = @import("utils.zig").check;
const Func = @import("utils.zig").Func;
const max_frames_inflight: usize = 3;

swapchain: vk.c.VkSwapchainKHR,
vk_images: [16]vk.c.VkImage,
image_count: u32,
format: vk.c.VkFormat,
width: u32,
height: u32,

current_frame_inflight: u32 = 0,
frames: [max_frames_inflight]FrameData = undefined,

pub fn init(physical_device: vk.PhysicalDevice, device: *vk.Device, command_pool: *vk.CommandPool, surface: *vk.Surface, width: u32, height: u32) !@This() {
    var swapchain: vk.c.VkSwapchainKHR = undefined;

    var capabilities: vk.c.VkSurfaceCapabilitiesKHR = undefined;
    try check(vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device.ptr, surface.toC(), &capabilities));

    var format_count: u32 = 0;
    try check(vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.ptr, surface.toC(), &format_count, null));

    var formats: [16]vk.c.VkSurfaceFormatKHR = undefined;
    try check(vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.ptr, surface.toC(), &format_count, &formats[0]));

    var chosen_format: vk.c.VkSurfaceFormatKHR = formats[0];
    for (0..format_count) |i| {
        if (formats[i].format == vk.c.VK_FORMAT_R8G8B8A8_SRGB) {
            chosen_format = formats[i];
            break;
        }
    }

    var swapchain_info: vk.c.VkSwapchainCreateInfoKHR = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface.toC(),
        .minImageCount = capabilities.minImageCount,
        .imageFormat = chosen_format.format,
        .imageColorSpace = chosen_format.colorSpace,
        .imageExtent = .{ .width = width, .height = height },
        .imageArrayLayers = 1,
        .imageUsage = vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = vk.c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = vk.c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk.c.VK_PRESENT_MODE_IMMEDIATE_KHR, //TODO: MAILBOX
        .clipped = 1,
    };

    try check(vk.c.vkCreateSwapchainKHR(device.toC(), &swapchain_info, null, &swapchain));

    var frames: [max_frames_inflight]FrameData = undefined;
    for (&frames) |*frame| frame.* = try .init(device, command_pool);

    return .{
        .swapchain = swapchain,
        .vk_images = undefined,
        .image_count = undefined,
        .format = chosen_format.format,
        .width = width,
        .height = height,
        .current_frame_inflight = 0,
        .frames = frames,
    };
}

pub fn deinit(
    self: @This(),
    device: *vk.Device,
    command_pool: *vk.CommandPool,
) void {
    for (self.frames) |frame| frame.deinit(device, command_pool);
    vk.c.vkDestroySwapchainKHR(device.toC(), self.swapchain, null);
}

// pub fn createSwapchainImages(
//     self: *@This(),
//     device: *vk.Device,
//     command_pool: *vk.CommandPool,
// ) !void {
//     try check(vk.c.vkGetSwapchainImagesKHR(device.toC(), self.swapchain, &self.image_count, null));
//     if (self.image_count > 16) @panic("More than 16 VkImages\n");

//     var vk_images: [16]vk.c.VkImage = undefined;
//     try check(vk.c.vkGetSwapchainImagesKHR(device.toC(), self.swapchain, &self.image_count, &vk_images[0]));

//     for (0..self.image_count) |i| {
//         self.images[i] = try .init(device, command_pool, vk_images[i]);
//     }
// }

pub fn recreate(
    self: *@This(),
    surface: vk.c.VkSurfaceKHR,
    physical_device: vk.VkPhysicalDevice,
    command_pool: vk.VkCommandPool,
    image_index: *u32,
    width: u32,
    height: u32,
) !void {
    try check(vk.c.vkDeviceWaitIdle(self.device));

    for (self.swapchain_images[0..@intCast(self.image_count)]) |image| image.deinit(self.device, command_pool);

    self.deinit();
    self.* = try init(physical_device, self.device, surface, width, height);

    try self.createSwapchainImages(command_pool);

    image_index.* = 0;
}

const FrameData = struct {
    command_buffer: vk.c.VkCommandBuffer,
    render_done_semaphore: vk.c.VkSemaphore,
    swapchain_semaphore: vk.c.VkSemaphore,
    render_fence: vk.c.VkFence,

    pub fn init(device: *vk.Device, command_pool: *vk.CommandPool) !@This() {
        var alloc_info: vk.c.VkCommandBufferAllocateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool.toC(),
            .level = vk.c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        var command_buffer: vk.c.VkCommandBuffer = undefined;
        try check(vk.c.vkAllocateCommandBuffers(device.toC(), &alloc_info, &command_buffer));

        var semaphoreCreateInfo: vk.c.VkSemaphoreCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        var render_done_semaphore: vk.c.VkSemaphore = undefined;
        try check(vk.c.vkCreateSemaphore(device.toC(), &semaphoreCreateInfo, null, &render_done_semaphore));

        var swapchain_semaphore: vk.c.VkSemaphore = undefined;
        try check(vk.c.vkCreateSemaphore(device.toC(), &semaphoreCreateInfo, null, &swapchain_semaphore));

        var fence_info: vk.c.VkFenceCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = vk.c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        var render_fence: vk.c.VkFence = undefined;
        try check(vk.c.vkCreateFence(device.toC(), &fence_info, null, &render_fence));

        return .{
            .command_buffer = command_buffer,
            .render_done_semaphore = render_done_semaphore,
            .swapchain_semaphore = swapchain_semaphore,
            .render_fence = render_fence,
        };
    }

    pub fn deinit(self: @This(), device: *vk.Device, command_pool: *vk.CommandPool) void {
        vk.c.vkDestroySemaphore(device.toC(), self.render_done_semaphore, null);
        vk.c.vkDestroySemaphore(device.toC(), self.swapchain_semaphore, null);
        vk.c.vkDestroyFence(device.toC(), self.render_fence, null);
        vk.c.vkFreeCommandBuffers(device.toC(), command_pool.toC(), 1, &self.command_buffer);
    }
};
