const std = @import("std");
const vk = @import("vulkan.zig");

_drawImageDescriptors: vk.c.VkDescriptorSet,
descriptor_pool: vk.c.VkDescriptorPool,
_drawImageDescriptorLayou: vk.c.VkDescriptorSetLayout,

//TODO: DONT TAKE IN  draw_iamge: vk.c.VkImage HERE
fn init(device: *vk.Device, draw_iamge: vk.c.VkImage) !@This() {
    const max_sets: i32 = 10;
    var descriptor_pool_size: []vk.c.VkDescriptorPoolSize = &.{
        .{ .descriptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 * max_sets },
    };

    var pool_info: vk.c.VkDescriptorPoolCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = 0,
        .maxSets = max_sets,
        .poolSizeCount = descriptor_pool_size.len,
        .pPoolSizes = &descriptor_pool_size,
    };

    var pool: vk.c.VkDescriptorPool = undefined;
    vk.c.vkCreateDescriptorPool(device.toC(), &pool_info, null, &pool);

    var new_bind: []vk.c.VkDescriptorSetLayoutBinding = &.{.{
        .binding = 0,
        .descriptorCount = 1,
        .descriptorType = vk.c.VK_SHADER_STAGE_COMPUTE_BIT | vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
    }};

    var descriptor_set_layout_info: vk.c.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = null,
        .pBindings = &new_bind,
        .bindingCount = new_bind.len,
        .flags = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
    };

    var set: vk.c.VkDescriptorSetLayout = undefined;
    vk.check((vk.c.vkCreateDescriptorSetLayout(device, &descriptor_set_layout_info, null, &set)));

    var alloc_info: vk.c.VkDescriptorSetAllocateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = &pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &set,
    };

    var ds: vk.c.VkDescriptorSet = undefined;
    vk.check(vk.c.vkAllocateDescriptorSets(device, &alloc_info, &ds));

    var img_info: vk.c.VkDescriptorImageInfo = .{
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_GENERAL,
        .imageView = draw_iamge.imageView,
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

    vk.c.vkUpdateDescriptorSets(device.toC(), 1, &drawImageWrite, 0, null);

    return .{
        ._drawImageDescriptorLayou = set,
        ._drawImageDescriptors = ds,
        .descriptor_pool = pool,
    };
}

fn deinit(self: @This(), device: vk.Device) !void {
    vk.c.vkFreeDescriptorSets(device.toC(), self.descriptor_pool, 1, self._drawImageDescriptors);
    vk.c.vkDestroyDescriptorPool(device, self.descriptor_pool, null);
    vk.c.vkDestroyDescriptorSetLayout(device, self._drawImageDescriptorLayou, null);
}
