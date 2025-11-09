const std = @import("std");
const vk = @import("vulkan.zig");

_drawImageDescriptors: vk.c.VkDescriptorSet,
descriptor_pool: vk.c.VkDescriptorPool,
_drawImageDescriptorLayou: vk.c.VkDescriptorSetLayout,

ratios: std.ArrayList(PoolSizeRatio) = .empty,
full_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty,
ready_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty,
sets_per_pool: u32 = 0,

const PoolSizeRatio = struct {
    desciptor_type: vk.c.VkDescriptorType,
    ratio: f32,
};

//TODO: DONT TAKE IN  draw_iamge: vk.c.VkImage HERE
pub fn init(device: vk.Device, draw_iamge: vk.c.VkImageView) !@This() {
    const max_sets: i32 = 10;
    const descriptor_pool_size: []const vk.c.VkDescriptorPoolSize = &.{
        .{ .type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 1 * max_sets },
    };

    var pool_info: vk.c.VkDescriptorPoolCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = vk.c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        .maxSets = max_sets,
        .poolSizeCount = @intCast(descriptor_pool_size.len),
        .pPoolSizes = @ptrCast(descriptor_pool_size),
    };

    var pool: vk.c.VkDescriptorPool = undefined;
    try vk.check(vk.c.vkCreateDescriptorPool(device.handle, &pool_info, null, &pool));

    const new_bind: []const vk.c.VkDescriptorSetLayoutBinding = &.{.{
        .binding = 0,
        .descriptorCount = 1,
        .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .stageFlags = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
    }};

    var descriptor_set_layout_info: vk.c.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @intCast(new_bind.len),
        .pBindings = @ptrCast(new_bind),
    };

    var set: vk.c.VkDescriptorSetLayout = undefined;
    try vk.check((vk.c.vkCreateDescriptorSetLayout(device.handle, &descriptor_set_layout_info, null, &set)));

    var alloc_info: vk.c.VkDescriptorSetAllocateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = @ptrCast(pool),
        .descriptorSetCount = 1,
        .pSetLayouts = &set,
    };

    var ds: vk.c.VkDescriptorSet = undefined;
    try vk.check(vk.c.vkAllocateDescriptorSets(device.handle, &alloc_info, &ds));

    var img_info: vk.c.VkDescriptorImageInfo = .{
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_GENERAL,
        .imageView = draw_iamge,
    };

    var drawImageWrite: vk.c.VkWriteDescriptorSet = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = null,
        .dstBinding = 0,
        .dstSet = ds,
        .descriptorCount = 1,
        .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &img_info,
    };

    vk.c.vkUpdateDescriptorSets(device.handle, 1, &drawImageWrite, 0, null);

    return .{
        ._drawImageDescriptorLayou = set,
        ._drawImageDescriptors = ds,
        .descriptor_pool = pool,
    };
}

pub fn deinit(self: @This(), device: vk.Device) void {
    _ = vk.c.vkFreeDescriptorSets(device.handle, self.descriptor_pool, 1, &self._drawImageDescriptors);
    vk.c.vkDestroyDescriptorPool(device.handle, self.descriptor_pool, null);
    vk.c.vkDestroyDescriptorSetLayout(device.handle, self._drawImageDescriptorLayou, null);
}
