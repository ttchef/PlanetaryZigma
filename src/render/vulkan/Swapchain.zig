const std = @import("std");
const vk = @import("vulkan.zig");
const check = @import("utils.zig").check;
const Func = @import("utils.zig").Func;
const max_frames_inflight: usize = 3;

swapchain: vk.c.VkSwapchainKHR,
vk_images: [16]vk.c.VkImage,
render_semaphores: [16]vk.c.VkSemaphore,
image_count: u32,
format: vk.c.VkFormat,
extent: vk.c.VkExtent3D,

current_frame_inflight: u32 = 0,
frames: [max_frames_inflight]FrameData = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.Surface,
    width: u32,
    height: u32,
) !@This() {
    const surface_format = try getSurfaceFormat(physical_device, surface);
    const swapchain = try createSwapchain(physical_device, device, surface, surface_format, width, height);

    var image_count: u32 = undefined;
    try check(vk.c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, null));
    if (image_count > 16) @panic("More than 16 VkImages\n");

    var vk_images: [16]vk.c.VkImage = undefined;
    try check(vk.c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, &vk_images[0]));

    var semaphoreCreateInfo: vk.c.VkSemaphoreCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var render_semaphores: [16]vk.c.VkSemaphore = undefined;
    for (0..image_count) |i| {
        var new_render_semaphore: vk.c.VkSemaphore = undefined;
        try check(vk.c.vkCreateSemaphore(device.handle, &semaphoreCreateInfo, null, &new_render_semaphore));
        render_semaphores[i] = new_render_semaphore;
    }

    var frames: [max_frames_inflight]FrameData = undefined;
    for (&frames) |*frame| frame.* = try .init(allocator, device);

    const actual_extent: vk.c.VkExtent2D = try getSurfaceExtent(physical_device, surface, width, height);

    return .{
        .swapchain = swapchain,
        .vk_images = vk_images,
        .render_semaphores = render_semaphores,
        .image_count = image_count,
        .format = surface_format.format,
        .extent = .{ .width = actual_extent.width, .height = actual_extent.height, .depth = 1 },
        .current_frame_inflight = 0,
        .frames = frames,
    };
}

pub fn deinit(
    self: *@This(),
    device: vk.Device,
) void {
    for (&self.frames) |*frame| frame.deinit(device);
    for (0..self.image_count) |i| {
        vk.c.vkDestroySemaphore(device.handle, self.render_semaphores[i], null);
    }
    vk.c.vkDestroySwapchainKHR(device.handle, self.swapchain, null);
}

pub fn recreate(
    self: *@This(),
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.Surface,
    width: u32,
    height: u32,
) !void {
    try check(vk.c.vkDeviceWaitIdle(device.handle));
    vk.c.vkDestroySwapchainKHR(device.handle, self.swapchain, null);

    const actual_extent = try getSurfaceExtent(physical_device, surface, width, height);

    const surface_format = try getSurfaceFormat(physical_device, surface);
    const swapchain = try createSwapchain(physical_device, device, surface, surface_format, actual_extent.width, actual_extent.height);
    self.swapchain = swapchain;

    self.extent = .{ .width = actual_extent.width, .height = actual_extent.height, .depth = 1 };
    var image_count: u32 = undefined;
    try check(vk.c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, null));
    if (image_count > 16) @panic("More than 16 VkImages\n");

    var vk_images: [16]vk.c.VkImage = undefined;
    try check(vk.c.vkGetSwapchainImagesKHR(device.handle, swapchain, &image_count, &vk_images[0]));
    self.vk_images = vk_images;
}

fn createSwapchain(
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    surface: vk.Surface,
    chosen_format: vk.c.VkSurfaceFormatKHR,
    width: u32,
    height: u32,
) !vk.c.VkSwapchainKHR {
    var swapchain: vk.c.VkSwapchainKHR = undefined;

    var capabilities: vk.c.VkSurfaceCapabilitiesKHR = undefined;
    try check(vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device.handle, surface.handle, &capabilities));

    const actual_extent: vk.c.VkExtent2D = try getSurfaceExtent(physical_device, surface, width, height);

    var swapchain_info: vk.c.VkSwapchainCreateInfoKHR = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface.handle,
        .minImageCount = capabilities.minImageCount,
        .imageFormat = chosen_format.format,
        .imageColorSpace = chosen_format.colorSpace,
        .imageExtent = actual_extent,
        .imageArrayLayers = 1,
        .imageUsage = vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = vk.c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = vk.c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = vk.c.VK_PRESENT_MODE_IMMEDIATE_KHR,
        .clipped = 1,
    };

    try check(vk.c.vkCreateSwapchainKHR(device.handle, &swapchain_info, null, &swapchain));

    return swapchain;
}

fn getSurfaceFormat(physical_device: vk.PhysicalDevice, surface: vk.Surface) !vk.c.VkSurfaceFormatKHR {
    var format_count: u32 = 0;
    try check(vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.handle, surface.handle, &format_count, null));

    var formats: [16]vk.c.VkSurfaceFormatKHR = undefined;
    try check(vk.c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device.handle, surface.handle, &format_count, &formats[0]));

    var chosen_format: vk.c.VkSurfaceFormatKHR = formats[0];
    for (0..format_count) |i| {
        if (formats[i].format == vk.c.VK_FORMAT_R8G8B8A8_SRGB) {
            chosen_format = formats[i];
            break;
        }
    }
    return chosen_format;
}

fn getSurfaceExtent(
    physical_device: vk.PhysicalDevice,
    surface: vk.Surface,
    width: u32,
    height: u32,
) !vk.c.VkExtent2D {
    var capabilities: vk.c.VkSurfaceCapabilitiesKHR = undefined;
    try check(vk.c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device.handle, surface.handle, &capabilities));

    const actual_extent: vk.c.VkExtent2D = if (capabilities.currentExtent.width != std.math.maxInt(u32) and
        capabilities.currentExtent.height != std.math.maxInt(u32))
        capabilities.currentExtent
    else
        .{
            .width = @max(capabilities.minImageExtent.width, @min(capabilities.maxImageExtent.width, width)),
            .height = @max(capabilities.minImageExtent.height, @min(capabilities.maxImageExtent.height, height)),
        };

    return actual_extent;
}

const FrameData = struct {
    swapchain_semaphore: vk.c.VkSemaphore,
    render_fence: vk.c.VkFence,
    command_buffer: vk.c.VkCommandBuffer,
    descriptor: vk.descriptor.Growable,
    gpu_scene: vk.Buffer = undefined, //TODO: CONTINUE from here LUCAS please fix this, poraro

    pub fn init(allocator: std.mem.Allocator, device: vk.Device) !@This() {
        var alloc_info: vk.c.VkCommandBufferAllocateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = device.command_pool.handle,
            .level = vk.c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        var command_buffer: vk.c.VkCommandBuffer = undefined;
        try check(vk.c.vkAllocateCommandBuffers(device.handle, &alloc_info, &command_buffer));

        var semaphoreCreateInfo: vk.c.VkSemaphoreCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };
        var swapchain_semaphore: vk.c.VkSemaphore = undefined;
        try check(vk.c.vkCreateSemaphore(device.handle, &semaphoreCreateInfo, null, &swapchain_semaphore));

        var fence_info: vk.c.VkFenceCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = vk.c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        var render_fence: vk.c.VkFence = undefined;
        try check(vk.c.vkCreateFence(device.handle, &fence_info, null, &render_fence));

        var frame_sizes = [_]vk.descriptor.Growable.PoolSizeRatio{
            .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 3 },
            .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .ratio = 3 },
            .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 3 },
            .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .ratio = 4 },
        };

        return .{
            .command_buffer = command_buffer,
            .swapchain_semaphore = swapchain_semaphore,
            .render_fence = render_fence,
            .descriptor = try .init(
                allocator,
                device,
                1000,
                &frame_sizes,
            ),
        };
    }

    pub fn deinit(self: *@This(), device: vk.Device) void {
        vk.c.vkDestroySemaphore(device.handle, self.swapchain_semaphore, null);
        vk.c.vkDestroyFence(device.handle, self.render_fence, null);
        vk.c.vkFreeCommandBuffers(device.handle, device.command_pool.handle, 1, &self.command_buffer);
        self.descriptor.deinit(device);
    }
};
