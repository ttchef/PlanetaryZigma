const c = @import("vulkan");

cmd: c.VkCommandBuffer,
image: c.VkImage,
aspect_mask: c.VkImageAspectFlags,

old_layout: c.VkImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
src_stage: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
src_access: c.VkAccessFlags = 0,

pub fn init(
    cmd: c.VkCommandBuffer,
    image: c.VkImage,
    aspect_mask: c.VkImageAspectFlags,
) @This() {
    return .{
        .cmd = cmd,
        .image = image,
        .aspect_mask = aspect_mask,
    };
}

pub fn transition(self: *@This(), layout: c.VkImageLayout, stage: c.VkPipelineStageFlags, access: c.VkAccessFlags) void {
    var new: c.VkImageMemoryBarrier = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        // .srcStageMask = src_stage,
        .srcAccessMask = self.src_access,
        // .dstStageMask = dst_stage,
        .dstAccessMask = access,
        .oldLayout = self.old_layout,
        .newLayout = layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = self.image,
        .subresourceRange = .{
            .aspectMask = self.aspect_mask,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    c.vkCmdPipelineBarrier(self.cmd, self.src_stage, stage, 0, 0, null, 0, null, 1, &new);
    self.*.old_layout = layout;
    self.*.src_stage = stage;
    self.*.src_access = access;
}

pub fn transitionMipLevel(
    self: *@This(),
    new_layout: c.VkImageLayout,
    dst_stage: c.VkPipelineStageFlags,
    dst_access: c.VkAccessFlags,
    level_count: u32,
    base_mip_level: u32,
    layer_count: u32,
) void {
    var new: c.VkImageMemoryBarrier2 = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = self.src_stage,
        .srcAccessMask = self.src_access,
        .dstStageMask = dst_stage,
        .dstAccessMask = dst_access,
        .oldLayout = self.old_layout,
        .newLayout = new_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = self.image,
        .subresourceRange = .{
            .aspectMask = self.aspect_mask,
            .baseMipLevel = base_mip_level,
            .levelCount = level_count,
            .baseArrayLayer = 0,
            .layerCount = layer_count,
        },
    };
    var dep: c.VkDependencyInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .pNext = null,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &new,
    };
    c.vkCmdPipelineBarrier2(self.cmd, &dep);
    self.*.old_layout = new_layout;
    self.*.src_stage = dst_stage;
    self.*.src_access = dst_access;
}
