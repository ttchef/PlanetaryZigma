const std = @import("std");
const vk = @import("vulkan.zig");

_drawImageDescriptors: vk.c.VkDescriptorSet,
descriptor_pool: vk.c.VkDescriptorPool,
_drawImageDescriptorLayou: vk.c.VkDescriptorSetLayout,
//TODO: DONT keep shader in descriptors?
shader: vk.c.VkShaderModule,

//TODO: DONT TAKE IN  draw_iamge: vk.c.VkImage HERE
pub fn init(device: *vk.Device, draw_iamge: vk.c.VkImageView) !@This() {
    const max_sets: i32 = 10;
    const descriptor_pool_size: []const vk.c.VkDescriptorPoolSize = &.{
        .{ .type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 1 * max_sets },
    };

    var pool_info: vk.c.VkDescriptorPoolCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = 0,
        .maxSets = max_sets,
        .poolSizeCount = @intCast(descriptor_pool_size.len),
        .pPoolSizes = @ptrCast(descriptor_pool_size),
    };

    var pool: vk.c.VkDescriptorPool = undefined;
    try vk.check(vk.c.vkCreateDescriptorPool(device.toC(), &pool_info, null, &pool));

    const new_bind: []const vk.c.VkDescriptorSetLayoutBinding = &.{.{
        .binding = 0,
        .descriptorCount = 1,
        .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    }};

    var descriptor_set_layout_info: vk.c.VkDescriptorSetLayoutCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = @intCast(new_bind.len),
        .pBindings = @ptrCast(new_bind),
    };

    var set: vk.c.VkDescriptorSetLayout = undefined;
    try vk.check((vk.c.vkCreateDescriptorSetLayout(device.toC(), &descriptor_set_layout_info, null, &set)));

    var alloc_info: vk.c.VkDescriptorSetAllocateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .pNext = null,
        .descriptorPool = @ptrCast(pool),
        .descriptorSetCount = 1,
        .pSetLayouts = &set,
    };

    var ds: vk.c.VkDescriptorSet = undefined;
    try vk.check(vk.c.vkAllocateDescriptorSets(device.toC(), &alloc_info, &ds));

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

    vk.c.vkUpdateDescriptorSets(device.toC(), 1, &drawImageWrite, 0, null);

    const shader = try loadShaderModule(device, "zig-out/shaders/gradient.comp.spv");

    return .{
        ._drawImageDescriptorLayou = set,
        ._drawImageDescriptors = ds,
        .descriptor_pool = pool,
        .shader = shader,
    };
}

pub fn deinit(self: @This(), device: *vk.Device) void {
    _ = vk.c.vkFreeDescriptorSets(device.toC(), self.descriptor_pool, 1, @ptrCast(@alignCast(self._drawImageDescriptors)));
    vk.c.vkDestroyShaderModule(device.toC(), self.shader, null);
    vk.c.vkDestroyDescriptorPool(device.toC(), self.descriptor_pool, null);
    vk.c.vkDestroyDescriptorSetLayout(device.toC(), self._drawImageDescriptorLayou, null);
}

fn loadShaderModule(device: *vk.Device, path: []const u8) !vk.c.VkShaderModule {
    const file: std.fs.File = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buffer: [4096]u8 = undefined;

    const n = try file.readAll(&buffer);
    const source = buffer[0..n];

    std.debug.print("buffer: \n{s}\n", .{buffer});
    std.debug.print("source: \n{s}\n", .{source});

    var create_info: vk.c.VkShaderModuleCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = n / 4,
        .pCode = @ptrCast(&source),
    };

    var shader_module: vk.c.VkShaderModule = undefined;
    try vk.check(vk.c.vkCreateShaderModule(device.toC(), &create_info, null, &shader_module));
    return shader_module;
}
