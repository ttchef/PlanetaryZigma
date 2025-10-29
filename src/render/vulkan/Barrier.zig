const c = @import("vulkan");

cmd: c.VkCommandBuffer,
image: c.VkImage,
layout: c.VkImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
stage: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
access: c.VkAccessFlags = 0,

pub fn init(cmd: c.VkCommandBuffer, image: c.VkImage) @This() {
    return .{
        .cmd = cmd,
        .image = image,
    };
}

pub fn transition(self: *@This(), layout: c.VkImageLayout, stage: c.VkPipelineStageFlags, access: c.VkAccessFlags) void {
    var new: c.VkImageMemoryBarrier = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        // .srcStageMask = src_stage,
        .srcAccessMask = self.access,
        // .dstStageMask = dst_stage,
        .dstAccessMask = access,
        .oldLayout = self.layout,
        .newLayout = layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = self.image,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    c.vkCmdPipelineBarrier(self.cmd, self.stage, stage, 0, 0, null, 0, null, 1, &new);
    self.*.layout = layout;
    self.*.stage = stage;
    self.*.access = access;
}
