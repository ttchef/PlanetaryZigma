const vk = @import("vulkan.zig");
const std = @import("std");

vk_image: vk.c.VkImage = undefined,
vk_imageview: vk.c.VkImageView = undefined,
vma_allocation: vk.Vma.Allocation = undefined,
extent: vk.c.VkExtent3D = undefined,
format: vk.c.VkFormat = undefined,
mip_mapped: bool = undefined,

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
        .extent = extent,
        .vk_image = image,
        .vk_imageview = image_view,
        .vma_allocation = vma_image_allocation,
        .mip_mapped = mip_mapped,
    };
}

pub fn deinit(self: @This(), vulkan_mem_alloc: vk.Vma, device: vk.Device) void {
    vk.c.vkDestroyImageView(device.handle, self.vk_imageview, null);
    vk.Vma.c.vmaDestroyImage(vulkan_mem_alloc.handle, @ptrCast(self.vk_image), self.vma_allocation);
}

pub fn uploadDataToImage(self: *@This(), device: vk.Device, vma: vk.Vma.Allocator, data: anytype) !void {
    const data_size: u32 = self.extent.depth * self.extent.width * self.extent.height * 4;
    const upload_buffer: vk.Buffer = try .init(
        vma,
        data_size,
        vk.c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .{
            .usage = vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .flags = vk.Vma.c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        },
    );
    defer upload_buffer.deinit(vma);

    @memcpy(
        @as([*]u8, @ptrCast(upload_buffer.info.pMappedData))[0..@intCast(data_size)],
        @as([*]u8, @ptrCast(data))[0..@intCast(data_size)],
    );

    const cmd = try device.beginImmediateCommand();

    var image_barrier: vk.ImageBarrier = .init(cmd, self.vk_image, vk.c.VK_IMAGE_ASPECT_COLOR_BIT);
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
        .imageExtent = self.extent,
    };

    vk.c.vkCmdCopyBufferToImage(
        cmd,
        upload_buffer.buffer,
        self.vk_image,
        vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &copy_region,
    );

    if (self.mip_mapped) {
        generateMipmaps(self, cmd, self.extent);
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

    var mip_levels_barrier: vk.ImageBarrier = .init(cmd_buffer, self.vk_image, vk.c.VK_IMAGE_ASPECT_COLOR_BIT);
    mip_levels_barrier.transitionMipLevel(
        vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        vk.c.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        @intCast(mip_levels),
        0,
        1,
    );

    for (0..mip_levels) |mip| {
        const half_size: vk.c.VkExtent3D = .{
            .height = size.height / 2,
            .width = size.width / 2,
        };
        mip_levels_barrier.old_layout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        mip_levels_barrier.src_access = vk.c.VK_ACCESS_2_TRANSFER_WRITE_BIT;
        mip_levels_barrier.src_stage = vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        mip_levels_barrier.transitionMipLevel(
            vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
            vk.c.VK_ACCESS_2_MEMORY_READ_BIT,
            1,
            @intCast(mip),
            vk.c.VK_REMAINING_ARRAY_LAYERS,
        );
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
            .dstImage = self.vk_image,
            .dstImageLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcImage = self.vk_image,
            .srcImageLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .filter = vk.c.VK_FILTER_LINEAR,
            .regionCount = 1,
        };

        vk.c.vkCmdBlitImage2(cmd_buffer, &blit_info);

        size = half_size;
    }
    mip_levels_barrier.transitionMipLevel(
        vk.c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        vk.c.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
        @intCast(mip_levels),
        0,
        1,
    );
}

pub fn copyOntoImage(
    self: @This(),
    cmd: vk.c.VkCommandBuffer,
    dest_image: @This(),
) void {
    var blit_region: vk.c.VkImageBlit2 = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .pNext = null,
        .srcOffsets = .{ .{}, .{
            .x = @intCast(self.extent.width),
            .y = @intCast(self.extent.height),
            .z = 1,
        } },
        .dstOffsets = .{ .{}, .{
            .x = @intCast(dest_image.extent.width),
            .y = @intCast(dest_image.extent.height),
            .z = 1,
        } },
        .srcSubresource = .{
            .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
        .dstSubresource = .{
            .aspectMask = vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .mipLevel = 0,
        },
    };

    var blit_info: vk.c.VkBlitImageInfo2 = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .pNext = null,
        .dstImage = dest_image.vk_image,
        .dstImageLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcImage = self.vk_image,
        .srcImageLayout = vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .filter = vk.c.VK_FILTER_LINEAR,
        .regionCount = 1,
        .pRegions = &blit_region,
    };

    vk.c.vkCmdBlitImage2(cmd, &blit_info);
}
