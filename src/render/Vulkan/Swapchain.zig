const std = @import("std");
const vk = @import("vulkan.zig");
const check = @import("utils.zig").check;
const Func = @import("utils.zig").Func;

swapchain: vk.c.VkSwapchainKHR,
images: [16]Image,
image_count: u32,
format: vk.c.VkFormat,
width: u32,
height: u32,

pub fn init(physical_device: *vk.PhysicalDevice, device: *vk.Device, surface: *vk.Surface, width: u32, height: u32) !@This() {
    var swapchain: vk.c.VkSwapchainKHR = undefined;

    var capabilities: vk.c.VkSurfaceCapabilitiesKHR = undefined;
    check(vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device.toC(), surface.toC(), &capabilities)) catch {
        std.log.err("\n\nMEGA ERR\n\n", .{});
        return error.aaa;
    };

    var formatCount: u32 = 0;
    try check(vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.toC(), surface.toC(), &formatCount, null));

    var formats: [16]vk.c.VkSurfaceFormatKHR = undefined;
    try check(vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.toC(), surface.toC(), &formatCount, &formats[0]));

    var chosenFormat: vk.c.VkSurfaceFormatKHR = formats[0];
    for (0..formatCount) |i| {
        if (formats[i].format == vk.c.VK_FORMAT_R8G8B8A8_SRGB) {
            chosenFormat = formats[i];
            break;
        }
    }

    var createInfo: vk.c.VkSwapchainCreateInfoKHR = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface.toC(),
        .minImageCount = capabilities.minImageCount,
        .imageFormat = chosenFormat.format,
        .imageColorSpace = chosenFormat.colorSpace,
        .imageExtent = .{ .width = width, .height = height },
        .imageArrayLayers = 1,
        .imageUsage = vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = vk.c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = vk.c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk.c.VK_PRESENT_MODE_IMMEDIATE_KHR, //TODO: MAILBOX
        .clipped = 1,
    };

    try check(vk.c.vkCreateSwapchainKHR(device.toC(), &createInfo, null, &swapchain));

    return .{
        .swapchain = swapchain,
        .images = undefined,
        .image_count = undefined,
        .format = chosenFormat.format,
        .width = width,
        .height = height,
    };
}

pub fn deinit(
    self: @This(),
    device: *vk.Device,
    command_pool: *vk.CommandPool,
) void {
    for (self.images[0..self.image_count]) |image| {
        image.deinit(device, command_pool);
    }
    vk.c.vkDestroySwapchainKHR(device.toC(), self.swapchain, null);
}

pub fn createSwapchainImages(
    self: *@This(),
    device: *vk.Device,
    command_pool: *vk.CommandPool,
) !void {
    try check(vk.c.vkGetSwapchainImagesKHR(device.toC(), self.swapchain, &self.image_count, null));
    if (self.image_count > 16) @panic("More than 16 VkImages\n");

    var vk_images: [16]vk.c.VkImage = undefined;
    try check(vk.c.vkGetSwapchainImagesKHR(device.toC(), self.swapchain, &self.image_count, &vk_images[0]));

    for (0..self.image_count) |i| {
        self.images[i] = try .init(device, command_pool, vk_images[i]);
    }
}

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

    for (0..self.image_count) |i| {
        self.swapchain_images[i].deinit(self.device, command_pool);
    }

    self.deinit();
    self.* = try init(physical_device, self.device, surface, width, height);

    try self.createSwapchainImages(command_pool);

    image_index.* = 0;
}

pub const Image = struct {
    vk_image: vk.c.VkImage,
    command_buffer: vk.c.VkCommandBuffer,
    render_done_semaphore: vk.c.VkSemaphore,

    pub fn init(device: *vk.Device, command_pool: *vk.CommandPool, image: vk.c.VkImage) !@This() {
        var allocInfo: vk.c.VkCommandBufferAllocateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool.toC(),
            .level = vk.c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        var command_buffer: vk.c.VkCommandBuffer = undefined;
        try check(vk.c.vkAllocateCommandBuffers(device.toC(), &allocInfo, &command_buffer));

        var semaphoreCreateInfo: vk.c.VkSemaphoreCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };

        var render_done_semaphore: vk.c.VkSemaphore = undefined;
        try check(vk.c.vkCreateSemaphore(device.toC(), &semaphoreCreateInfo, null, &render_done_semaphore));

        return .{
            .vk_image = image,
            .command_buffer = command_buffer,
            .render_done_semaphore = render_done_semaphore,
        };
    }

    pub fn deinit(self: @This(), device: *vk.Device, command_pool: *vk.CommandPool) void {
        vk.c.vkDestroySemaphore(device.toC(), self.render_done_semaphore, null);
        vk.c.vkFreeCommandBuffers(device.toC(), command_pool.toC(), 1, &self.command_buffer);
    }
};
