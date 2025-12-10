const std = @import("std");
const vk = @import("vulkan.zig");

image: vk.c.VkImage = undefined,
image_view: vk.c.VkImageView = undefined,
vma_allocation: vk.Vma.Allocation = undefined,
image_extent: vk.c.VkExtent3D = undefined,
format: vk.c.VkFormat = undefined,

pub fn init(
    vma: vk.Vma.Allocator,
    device: vk.Device,
    format: vk.c.VkFormat,
    extent: vk.c.VkExtent3D,
    image_usages_flags: vk.c.VkImageUsageFlags,
    image_view_mask: vk.c.VkImageAspectFlags,
    mip_mapped: bool,
) !@This() {
    var img_info: vk.c.VkImageCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .imageType = vk.c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = vk.c.VK_IMAGE_TILING_OPTIMAL,
        .usage = image_usages_flags,
    };

    const max: f32 = @floatFromInt(@max(extent.width, extent.height));
    if (mip_mapped) img_info.mipLevels = @intFromFloat(@floor(@log2(max)) + 1);

    var vma_alloc_info: vk.Vma.c.VmaAllocationCreateInfo = .{
        .usage = vk.Vma.c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    var image: vk.c.VkImage = undefined;
    var vma_image_allocation: vk.Vma.Allocation = undefined;
    _ = vk.Vma.c.vmaCreateImage(
        vma,
        @ptrCast(&img_info),
        &vma_alloc_info,
        @ptrCast(&image),
        &vma_image_allocation,
        null,
    );

    var image_view_info: vk.c.VkImageViewCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = vk.c.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = .{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = image_view_mask,
        },
    };

    var image_view: vk.c.VkImageView = undefined;
    try vk.check(vk.c.vkCreateImageView(device.handle, &image_view_info, null, &image_view));

    return .{
        .format = format,
        .image_extent = extent,
        .image = image,
        .image_view = image_view,
        .vma_allocation = vma_image_allocation,
    };
}

pub fn uploadDataToImage(self: @This(), device: vk.Device, vma: vk.Vma.Allocator, data: anytype) !void {
    const data_size: u32 = self.image_extent.depth * self.image_extent.width * self.image_extent.height * 4;
    const upload_buffer: vk.Buffer = try .init(vma, data_size, vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    defer upload_buffer.deinit(vma);

    @memcpy(
        @as([*]u8, @ptrCast(upload_buffer.info.pMappedData))[0..@intCast(data_size)],
        std.mem.asBytes(data)[0..@intCast(data_size)],
    );

    const cmd = try device.beginImmediateCommand();

    var image_barrier: vk.Barrier = .init(cmd, self.image, vk.c.VK_IMAGE_ASPECT_COLOR_BIT);
    image_barrier.transition(
        vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_TRANSFER_BIT,
        vk.c.VK_ACCESS_MEMORY_WRITE_BIT,
    );

    var copy_region: vk.c.VkBufferImageCopy = .{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageExtent = self.image_extent,
    };

    vk.c.vkCmdCopyBufferToImage(
        cmd,
        upload_buffer.buffer,
        self.image,
        vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &copy_region,
    );

    image_barrier.transition(
        vk.c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        0,
        0,
    );

    try device.endImmediateCommand(cmd);
}

pub fn deinit(self: @This(), vulkan_mem_alloc: vk.Vma, device: vk.Device) void {
    vk.c.vkDestroyImageView(device.handle, self.image_view, null);
    vk.Vma.c.vmaDestroyImage(vulkan_mem_alloc.handle, @ptrCast(self.image), self.vma_allocation);
}
