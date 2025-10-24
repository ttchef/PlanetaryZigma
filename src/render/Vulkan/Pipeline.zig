const std = @import("std");
const vk = @import("vulkan.zig");
const nz = @import("numz");

pipeline: vk.c.VkPipeline,
pipeline_layout: vk.c.VkPipelineLayout,
data: ComputePushConstant,

pub const ComputePushConstant = struct {
    data1: nz.Vec4(f32),
    data2: nz.Vec4(f32),
    data3: nz.Vec4(f32),
    data4: nz.Vec4(f32),
};

pub fn init(device: *vk.Device, _drawImageDescriptorLayout: vk.c.VkDescriptorSetLayout, shader: vk.c.VkShaderModule) !@This() {
    var push_constant: vk.c.VkPushConstantRange = .{
        .offset = 0,
        .size = @sizeOf(ComputePushConstant),
        .stageFlags = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
    };

    var computeLayout: vk.c.VkPipelineLayoutCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pSetLayouts = &_drawImageDescriptorLayout,
        .setLayoutCount = 1,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &push_constant,
    };

    var pipeline_layout: vk.c.VkPipelineLayout = undefined;
    try vk.check(vk.c.vkCreatePipelineLayout(device.toC(), &computeLayout, null, &pipeline_layout));

    const stage_info: vk.c.VkPipelineShaderStageCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = shader,
        .pName = "main",
    };
    var computePipelineCreateInfo: vk.c.VkComputePipelineCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .layout = pipeline_layout,
        .stage = stage_info,
    };

    var pipeline: vk.c.VkPipeline = undefined;
    try vk.check(vk.c.vkCreateComputePipelines(device.toC(), null, 1, &computePipelineCreateInfo, null, &pipeline));
    return .{
        .pipeline = pipeline,
        .pipeline_layout = pipeline_layout,
        .data = .{
            .data1 = @splat(0),
            .data2 = @splat(0),
            .data3 = @splat(0),
            .data4 = @splat(0),
        },
    };
}

pub fn deinit(self: @This(), device: *vk.Device) void {
    vk.c.vkDestroyPipeline(device.toC(), self.pipeline, null);
    vk.c.vkDestroyPipelineLayout(device.toC(), self.pipeline_layout, null);
}
