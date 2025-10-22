const std = @import("std");
const vk = @import("vulkan.zig");

pipeline: vk.c.VkPipeline,
pipeline_layout: vk.c.VkPipelineLayout,

pub fn init(device: *vk.Device, _drawImageDescriptorLayout: vk.c.VkDescriptorSetLayout, shader: vk.c.VkShaderModule) !@This() {
    var computeLayout: vk.c.VkPipelineLayoutCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pSetLayouts = &_drawImageDescriptorLayout,
        .setLayoutCount = 1,
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
    };
}
