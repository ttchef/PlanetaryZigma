const std = @import("std");
const c = @import("vulkan");
const Vma = @import("Vma.zig");
const Func = @import("utils.zig").Func;
const PhysicalDevice = @import("device.zig").Physical;
const Device = @import("device.zig").Logical;
const Surface = @import("Surface.zig");
const check = @import("utils.zig").check;

const max_frames_inflight: usize = 3;
swapchain: c.VkSwapchainKHR,
vk_images: [16]c.VkImage,
render_semaphores: [16]c.VkSemaphore,
image_count: u32,
format: c.VkFormat,
extent: c.VkExtent3D,

current_frame_inflight: u32 = 0,
frames: [max_frames_inflight]FrameData = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    vma: Vma,
    physical_device: PhysicalDevice,
    device: Device,
    surface: Surface,
    width: u32,
    height: u32,
) !@This() {
    const surface_format = try getSurfaceFormat(allocator, physical_device, surface);
    const swapchain = try createSwapchain(physical_device, device, surface, surface_format, width, height);

    var image_count: u32 = undefined;
    try check(c.vkGetSwapchainImagesKHR.?(device.handle, swapchain, &image_count, null));
    if (image_count > 16) @panic("More than 16 VkImages\n");

    var vk_images: [16]c.VkImage = undefined;
    try check(c.vkGetSwapchainImagesKHR.?(device.handle, swapchain, &image_count, &vk_images[0]));

    var semaphoreCreateInfo: c.VkSemaphoreCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var render_semaphores: [16]c.VkSemaphore = undefined;
    for (0..image_count) |i| {
        var new_render_semaphore: c.VkSemaphore = undefined;
        try check(c.vkCreateSemaphore.?(device.handle, &semaphoreCreateInfo, null, &new_render_semaphore));
        render_semaphores[i] = new_render_semaphore;
    }

    var frames: [max_frames_inflight]FrameData = undefined;
    for (&frames) |*frame| {
        frame.* = try .init(vma, device);
        // std.debug.print("PTR: {*}\n", .{&frame.gpu_scene.buffer});
    }

    const actual_extent: c.VkExtent2D = try getSurfaceExtent(physical_device, surface, width, height);

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
    vma: Vma,
    device: Device,
) void {
    for (&self.frames) |*frame| frame.deinit(vma, device);
    for (0..self.image_count) |i| {
        c.vkDestroySemaphore.?(device.handle, self.render_semaphores[i], null);
    }
    c.vkDestroySwapchainKHR.?(device.handle, self.swapchain, null);
}

pub fn recreate(
    self: *@This(),
    allocator: std.mem.Allocator,
    physical_device: PhysicalDevice,
    device: Device,
    surface: Surface,
    width: u32,
    height: u32,
) !void {
    try check(c.vkDeviceWaitIdle.?(device.handle));
    c.vkDestroySwapchainKHR.?(device.handle, self.swapchain, null);

    const actual_extent = try getSurfaceExtent(physical_device, surface, width, height);

    const surface_format = try getSurfaceFormat(allocator, physical_device, surface);
    const swapchain = try createSwapchain(physical_device, device, surface, surface_format, actual_extent.width, actual_extent.height);
    self.swapchain = swapchain;

    self.extent = .{ .width = actual_extent.width, .height = actual_extent.height, .depth = 1 };
    var image_count: u32 = undefined;
    try check(c.vkGetSwapchainImagesKHR.?(device.handle, swapchain, &image_count, null));
    if (image_count > 16) @panic("More than 16 VkImages\n");

    var vk_images: [16]c.VkImage = undefined;
    try check(c.vkGetSwapchainImagesKHR.?(device.handle, swapchain, &image_count, &vk_images[0]));
    self.vk_images = vk_images;
}

fn createSwapchain(
    physical_device: PhysicalDevice,
    device: Device,
    surface: Surface,
    chosen_format: c.VkSurfaceFormatKHR,
    width: u32,
    height: u32,
) !c.VkSwapchainKHR {
    var swapchain: c.VkSwapchainKHR = undefined;

    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(physical_device.handle, surface.handle, &capabilities));

    const actual_extent: c.VkExtent2D = try getSurfaceExtent(physical_device, surface, width, height);

    var swapchain_info: c.VkSwapchainCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = surface.handle,
        .minImageCount = capabilities.minImageCount,
        .imageFormat = chosen_format.format,
        .imageColorSpace = chosen_format.colorSpace,
        .imageExtent = actual_extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = c.VK_PRESENT_MODE_IMMEDIATE_KHR,
        .clipped = 1,
    };

    try check(c.vkCreateSwapchainKHR.?(device.handle, &swapchain_info, null, &swapchain));

    return swapchain;
}

fn getSurfaceFormat(allocator: std.mem.Allocator, physical_device: PhysicalDevice, surface: Surface) !c.VkSurfaceFormatKHR {
    var format_count: u32 = 0;
    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR.?(physical_device.handle, surface.handle, &format_count, null));

    const formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
    defer allocator.free(formats);
    try check(c.vkGetPhysicalDeviceSurfaceFormatsKHR.?(physical_device.handle, surface.handle, &format_count, formats.ptr));

    var chosen_format: c.VkSurfaceFormatKHR = formats[0];
    for (0..format_count) |i| {
        if (formats[i].format == c.VK_FORMAT_R8G8B8A8_UNORM) {
            chosen_format = formats[i];
            break;
        }
    }
    return chosen_format;
}

fn getSurfaceExtent(
    physical_device: PhysicalDevice,
    surface: Surface,
    width: u32,
    height: u32,
) !c.VkExtent2D {
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(physical_device.handle, surface.handle, &capabilities));

    const actual_extent: c.VkExtent2D = if (capabilities.currentExtent.width != std.math.maxInt(u32) and
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
    swapchain_semaphore: c.VkSemaphore,
    render_fence: c.VkFence,
    command_buffer: c.VkCommandBuffer,
    // gpu_scene: Buffer,

    pub fn init(vma: Vma, device: Device) !@This() {
        _ = vma;
        var alloc_info: c.VkCommandBufferAllocateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = device.command_pool.handle,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };

        var command_buffer: c.VkCommandBuffer = undefined;
        try check(c.vkAllocateCommandBuffers.?(device.handle, &alloc_info, &command_buffer));

        var semaphoreCreateInfo: c.VkSemaphoreCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        };
        var swapchain_semaphore: c.VkSemaphore = undefined;
        try check(c.vkCreateSemaphore.?(device.handle, &semaphoreCreateInfo, null, &swapchain_semaphore));

        var fence_info: c.VkFenceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        var render_fence: c.VkFence = undefined;
        try check(c.vkCreateFence.?(device.handle, &fence_info, null, &render_fence));

        return .{
            .command_buffer = command_buffer,
            .swapchain_semaphore = swapchain_semaphore,
            .render_fence = render_fence,

            // .gpu_scene = try .init(
            //     vma.handle,
            //     @sizeOf(GPUSceneData),
            //     c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            //     .{
            //         .usage = Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU,
            //         .flags = Vma.c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            //     },
            // ),
        };
    }

    pub fn deinit(self: *@This(), vma: Vma, device: Device) void {
        c.vkDestroySemaphore.?(device.handle, self.swapchain_semaphore, null);
        c.vkDestroyFence.?(device.handle, self.render_fence, null);
        c.vkFreeCommandBuffers.?(device.handle, device.command_pool.handle, 1, &self.command_buffer);
        self.descriptor.deinit(device);
        self.gpu_scene.deinit(vma.handle);
    }
};
