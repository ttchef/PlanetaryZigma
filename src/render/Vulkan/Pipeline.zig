const std = @import("std");
const vk = @import("vulkan.zig");
const nz = @import("numz");

handle: vk.c.VkPipeline,
layout: vk.c.VkPipelineLayout,

data: union { compute: ComputePushConstant },

pub const ComputePushConstant = struct {
    data1: nz.Vec4(f32),
    data2: nz.Vec4(f32),
    data3: nz.Vec4(f32),
    data4: nz.Vec4(f32),
};

pub const Config = union(enum) {
    compute: Compute,
    graphics: Graphics,

    pub const Compute = struct {
        shader_stage: vk.c.VkPipelineShaderStageCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
            .module = null,
            .pName = "main",
            .pSpecializationInfo = null,
        },
        create_info: vk.c.VkComputePipelineCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = undefined,
            .layout = null,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
        },

        pub fn init() Compute {
            var self = Compute{};
            self.create_info.stage = self.shader_stage;
            return self;
        }
    };

    pub const Graphics = struct {
        vertex_input: vk.c.VkPipelineVertexInputStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .vertexBindingDescriptionCount = 0,
            .pVertexBindingDescriptions = null,
            .vertexAttributeDescriptionCount = 0,
            .pVertexAttributeDescriptions = null,
        },
        input_assembly: vk.c.VkPipelineInputAssemblyStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .pNext = null,
            .topology = vk.c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = 0,
        },
        rasterizer: vk.c.VkPipelineRasterizationStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .polygonMode = vk.c.VK_POLYGON_MODE_FILL,
            .cullMode = vk.c.VK_CULL_MODE_BACK_BIT,
            .frontFace = vk.c.VK_FRONT_FACE_CLOCKWISE,
            .lineWidth = 1.0,
        },
        multisample: vk.c.VkPipelineMultisampleStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .rasterizationSamples = vk.c.VK_SAMPLE_COUNT_1_BIT,
        },
        color_blend: vk.c.VkPipelineColorBlendStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = 0,
            .attachmentCount = 0,
            .pAttachments = null,
        },

        create_info: vk.c.VkGraphicsPipelineCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stageCount = 0,
            .pStages = null,
            .pVertexInputState = undefined,
            .pInputAssemblyState = undefined,
            .pTessellationState = null,
            .pViewportState = null,
            .pRasterizationState = undefined,
            .pMultisampleState = undefined,
            .pDepthStencilState = null,
            .pColorBlendState = undefined,
            .pDynamicState = null,
            .layout = null,
            .renderPass = null,
            .subpass = 0,
            .basePipelineHandle = null,
            .basePipelineIndex = -1,
        },

        pub fn init() Graphics {
            var self = Graphics{};
            self.create_info.pVertexInputState = &self.vertex_input;
            self.create_info.pInputAssemblyState = &self.input_assembly;
            self.create_info.pRasterizationState = &self.rasterizer;
            self.create_info.pMultisampleState = &self.multisample;
            self.create_info.pColorBlendState = &self.color_blend;
            return self;
        }
    };
};

pub fn init(device: *vk.Device, config: *Config, _drawImageDescriptorLayout: vk.c.VkDescriptorSetLayout, shader: vk.c.VkShaderModule) !@This() {
    var pipeline_layout: vk.c.VkPipelineLayout = undefined;
    var pipeline: vk.c.VkPipeline = undefined;

    switch (config.*) {
        .compute => {
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

            try vk.check(vk.c.vkCreatePipelineLayout(device.toC(), &computeLayout, null, &pipeline_layout));
            config.compute.create_info.stage = config.compute.shader_stage;
            config.compute.create_info.stage.module = shader;
            config.compute.create_info.layout = pipeline_layout;
            try vk.check(vk.c.vkCreateComputePipelines(device.toC(), null, 1, &config.compute.create_info, null, &pipeline));
        },
        .graphics => {},
    }

    return .{
        .handle = pipeline,
        .layout = pipeline_layout,
        .data = .{ .compute = .{
            .data1 = @splat(0),
            .data2 = @splat(0),
            .data3 = @splat(0),
            .data4 = @splat(0),
        } },
    };
}

pub fn deinit(self: @This(), device: *vk.Device) void {
    vk.c.vkDestroyPipeline(device.toC(), self.handle, null);
    vk.c.vkDestroyPipelineLayout(device.toC(), self.layout, null);
}
