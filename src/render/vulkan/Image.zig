const vk = @import("vulkan.zig");
const std = @import("std");

image: vk.c.VkImage = undefined,
image_view: vk.c.VkImageView = undefined,
vma_allocation: vk.Vma.Allocation = undefined,
image_extent: vk.c.VkExtent3D = undefined,
format: vk.c.VkFormat = undefined,
mip_mapped: bool,

pub fn init(
    vma: vk.Vma.Allocator,
    device: vk.Device,
    format: vk.c.VkFormat,
    extent: vk.c.VkExtent3D,
    image_usages_flags: vk.c.VkImageUsageFlags,
    image_view_mask: vk.c.VkImageAspectFlags,
    mip_mapped: bool,
) !@This() {
    var image_info: vk.c.VkImageCreateInfo = .{
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
    if (mip_mapped) {
        image_info.mipLevels = @as(u32, @intFromFloat(@floor(@log2(max)))) + 1;
    }

    var vma_alloc_info: vk.Vma.c.VmaAllocationCreateInfo = .{
        .usage = vk.Vma.c.VMA_MEMORY_USAGE_GPU_ONLY,
        .requiredFlags = vk.c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    var image: vk.c.VkImage = undefined;
    var vma_image_allocation: vk.Vma.Allocation = undefined;
    _ = vk.Vma.c.vmaCreateImage(
        vma,
        @ptrCast(&image_info),
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
            .levelCount = image_info.mipLevels,
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
        .mip_mapped = mip_mapped,
    };
}

pub fn deinit(self: @This(), vulkan_mem_alloc: vk.Vma, device: vk.Device) void {
    vk.c.vkDestroyImageView(device.handle, self.image_view, null);
    vk.Vma.c.vmaDestroyImage(vulkan_mem_alloc.handle, @ptrCast(self.image), self.vma_allocation);
}

pub fn uploadDataToImage(self: *@This(), device: vk.Device, vma: vk.Vma.Allocator, data: anytype) !void {
    const data_size: u32 = self.image_extent.depth * self.image_extent.width * self.image_extent.height * 4;
    const upload_buffer: vk.Buffer = try .init(vma, data_size, vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    defer upload_buffer.deinit(vma);

    @memcpy(
        @as([*]u8, @ptrCast(upload_buffer.info.pMappedData))[0..@intCast(data_size)],
        @as([*]u8, @ptrCast(data))[0..@intCast(data_size)],
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

    if (self.mip_mapped) {
        generateMipmaps(self, cmd, self.image_extent);
    } else {
        image_barrier.transition(
            vk.c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            0,
            0,
        );
    }

    try device.endImmediateCommand(cmd);
}

fn generateMipmaps(self: *@This(), cmd_buffer: vk.c.VkCommandBuffer, image_size: vk.c.VkExtent3D) void {
    var size = image_size;
    const mip_levels: usize = @as(usize, @intFromFloat(@floor(@log2(@as(f32, @floatFromInt(@max(size.width, size.height))))))) + 1;
    {
        var b: vk.c.VkImageMemoryBarrier2 = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = vk.c.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
            .srcAccessMask = 0,
            .dstStageMask = vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            .dstAccessMask = vk.c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .oldLayout = vk.c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
            .image = self.image,
            .subresourceRange = .{
                .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = @intCast(mip_levels),
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        var dep: vk.c.VkDependencyInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .pNext = null,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &b,
        };
        vk.c.vkCmdPipelineBarrier2(cmd_buffer, &dep);
    }

    for (0..mip_levels) |mip| {
        const half_size: vk.c.VkExtent3D = .{
            .height = size.height / 2,
            .width = size.width / 2,
        };
        var image_barrier: vk.c.VkImageMemoryBarrier2 = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            .srcAccessMask = vk.c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .dstStageMask = vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            .dstAccessMask = vk.c.VK_ACCESS_2_MEMORY_WRITE_BIT | vk.c.VK_ACCESS_2_MEMORY_READ_BIT,
            .oldLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .subresourceRange = .{
                .levelCount = 1,
                .baseMipLevel = @intCast(mip),
                .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseArrayLayer = 0,
                .layerCount = vk.c.VK_REMAINING_ARRAY_LAYERS,
            },
            .image = self.image,
        };
        var dep_info: vk.c.VkDependencyInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .pNext = null,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &image_barrier,
        };

        vk.c.vkCmdPipelineBarrier2(cmd_buffer, &dep_info);

        if (mip >= mip_levels - 1) continue;

        var blit_info: vk.c.VkBlitImageInfo2 = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
            .pNext = null,
            .pRegions = &.{
                .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
                .pNext = null,
                .srcOffsets = .{
                    .{},
                    .{
                        .x = @intCast(size.width),
                        .y = @intCast(size.height),
                        .z = 1,
                    },
                },
                .dstOffsets = .{
                    .{},
                    .{
                        .x = @intCast(half_size.width),
                        .y = @intCast(half_size.height),
                        .z = 1,
                    },
                },
                .srcSubresource = .{
                    .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                    .mipLevel = @intCast(mip),
                },
                .dstSubresource = .{
                    .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                    .mipLevel = @intCast(mip + 1),
                },
            },
            .dstImage = self.image,
            .dstImageLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcImage = self.image,
            .srcImageLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .filter = vk.c.VK_FILTER_LINEAR,
            .regionCount = 1,
        };

        vk.c.vkCmdBlitImage2(cmd_buffer, &blit_info);

        size = half_size;
    }
    // transition all mip levels into the final read_only layout
    {
        var b: vk.c.VkImageMemoryBarrier2 = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            .srcAccessMask = 0,
            .dstStageMask = vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            .dstAccessMask = vk.c.VK_ACCESS_2_TRANSFER_READ_BIT,
            .oldLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .newLayout = vk.c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.c.VK_QUEUE_FAMILY_IGNORED,
            .image = self.image,
            .subresourceRange = .{
                .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = @intCast(mip_levels),
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        var dep: vk.c.VkDependencyInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .pNext = null,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &b,
        };
        vk.c.vkCmdPipelineBarrier2(cmd_buffer, &dep);
    }
}
