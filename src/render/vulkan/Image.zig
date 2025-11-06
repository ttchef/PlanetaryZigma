const vk = @import("vulkan.zig");
const vma = @import("vma");

image: vk.c.VkImage = undefined,
image_view: vk.c.VkImageView = undefined,
vma_allocation: vma.VmaAllocation = undefined,
image_extent: vk.c.VkExtent3D = undefined,
format: vk.c.VkFormat = undefined,

pub fn init(
    vulkan_mem_alloc: vma.VmaAllocator,
    device: vk.Device,
    format: vk.c.VkFormat,
    extent: vk.c.VkExtent3D,
    image_usages_flags: vk.c.VkImageUsageFlags,
    image_view_mask: vk.c.VkImageAspectFlags,
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

    var vma_alloc_info: vma.VmaAllocationCreateInfo = .{
        .usage = vma.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    var image: vk.c.VkImage = undefined;
    var vma_image_allocation: vma.VmaAllocation = undefined;
    _ = vma.vmaCreateImage(
        vulkan_mem_alloc,
        @ptrCast(&img_info),
        &vma_alloc_info,
        &image,
        &vma_image_allocation,
        null,
    );

    var image_view_info: vk.c.VkImageViewCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
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

pub fn deinit(self: @This(), vulkan_mem_alloc: vk.Vma, device: vk.Device) void {
    vk.c.vkDestroyImageView(device.handle, self.image_view, null);
    vma.vmaDestroyImage(vulkan_mem_alloc.handle, @ptrCast(self.image), self.vma_allocation);
}
