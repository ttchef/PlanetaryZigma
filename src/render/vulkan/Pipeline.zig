const std = @import("std");
const vk = @import("vulkan.zig");
const nz = @import("numz");

pub const PipelineError = error{
    ComputePipelineRequiresExactlyOneShader,
    GraphicsPipelineRequiresAtLeastOneShader,
    GraphicsPipelineRequiresVertexShader,
    InvalidLineWidth,
    InvalidDepthBounds,
    ViewportScissorCountMismatch,
};

// Helper function to create shader stage create info from shader module
fn createShaderStageCreateInfo(module: vk.c.VkShaderModule, stage: vk.c.VkShaderStageFlagBits) vk.c.VkPipelineShaderStageCreateInfo {
    return .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = stage,
        .module = module,
        .pName = "main",
        .pSpecializationInfo = null,
    };
}

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

    pub fn defaultCompute() Config {
        return .{ .compute = Compute.init() };
    }

    pub fn defaultGraphics() Config {
        return .{ .graphics = Graphics.init() };
    }

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
        viewport: vk.c.VkPipelineViewportStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .viewportCount = 1,
            .pViewports = null,
            .scissorCount = 1,
            .pScissors = null,
        },
        depth_stencil: vk.c.VkPipelineDepthStencilStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .depthTestEnable = 1,
            .depthWriteEnable = 1,
            .depthCompareOp = vk.c.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = 0,
            .stencilTestEnable = 0,
            .front = .{ .failOp = 0, .passOp = 0, .depthFailOp = 0, .compareOp = 0, .compareMask = 0, .writeMask = 0, .reference = 0 },
            .back = .{ .failOp = 0, .passOp = 0, .depthFailOp = 0, .compareOp = 0, .compareMask = 0, .writeMask = 0, .reference = 0 },
            .minDepthBounds = 0,
            .maxDepthBounds = 1,
        },
        dynamic_states: [2]vk.c.VkDynamicState = .{ vk.c.VK_DYNAMIC_STATE_VIEWPORT, vk.c.VK_DYNAMIC_STATE_SCISSOR },
        dynamic_state: vk.c.VkPipelineDynamicStateCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .dynamicStateCount = 2,
            .pDynamicStates = undefined, // Will be set in init()
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
            var self: Graphics = .{};

            // Initialize missing fields in rasterizer
            self.rasterizer.sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
            self.rasterizer.flags = 0;
            self.rasterizer.depthClampEnable = 0;
            self.rasterizer.rasterizerDiscardEnable = 0;
            self.rasterizer.depthBiasConstantFactor = 0;
            self.rasterizer.depthBiasClamp = 0;
            self.rasterizer.depthBiasSlopeFactor = 0;

            // Initialize missing fields in input assembly
            self.input_assembly.sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
            self.input_assembly.flags = 0;

            // Initialize missing fields in multisample
            self.multisample.flags = 0;
            self.multisample.sampleShadingEnable = 0;
            self.multisample.minSampleShading = 1.0;
            self.multisample.pSampleMask = null;
            self.multisample.alphaToCoverageEnable = 0;
            self.multisample.alphaToOneEnable = 0;

            // Initialize missing fields in color blend
            self.color_blend.flags = 0;
            self.color_blend.logicOp = vk.c.VK_LOGIC_OP_COPY;
            self.color_blend.blendConstants = .{ 0, 0, 0, 0 };

            // Set dynamic states pointer
            self.dynamic_state.pDynamicStates = &self.dynamic_states;

            return self;
        }
    };
};

pub fn init(device: vk.Device, config: *Config, _drawImageDescriptorLayout: vk.c.VkDescriptorSetLayout, shaders: []const vk.c.VkShaderModule) !@This() {
    // Validate configuration before proceeding
    try validateConfig(config, shaders);

    var pipeline_layout: vk.c.VkPipelineLayout = undefined;
    var pipeline: vk.c.VkPipeline = undefined;

    switch (config.*) {
        .compute => {
            if (shaders.len != 1) return error.ComputePipelineRequiresExactlyOneShader;

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

            try vk.check(vk.c.vkCreatePipelineLayout(device.handle, &computeLayout, null, &pipeline_layout));
            config.compute.create_info.stage = config.compute.shader_stage;
            config.compute.create_info.stage.module = shaders[0];
            config.compute.create_info.layout = pipeline_layout;
            try vk.check(vk.c.vkCreateComputePipelines(device.handle, null, 1, &config.compute.create_info, null, &pipeline));
        },
        .graphics => {
            // Additional graphics-specific validation
            try validateGraphicsConfig(&config.graphics);

            var push_constant: vk.c.VkPushConstantRange = .{
                .offset = 0,
                .size = @sizeOf(ComputePushConstant), // TODO: Add graphics push constants if needed
                .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            };
            var graphicsLayout: vk.c.VkPipelineLayoutCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .pSetLayouts = &_drawImageDescriptorLayout,
                .setLayoutCount = 1,
                .pushConstantRangeCount = 1,
                .pPushConstantRanges = &push_constant,
            };

            try vk.check(vk.c.vkCreatePipelineLayout(device.handle, &graphicsLayout, null, &pipeline_layout));

            // Create shader stage create infos from shader modules
            var shader_stages: [4]vk.c.VkPipelineShaderStageCreateInfo = undefined;
            var stage_count: u32 = 0;

            // Assume first shader is vertex, second is fragment (if present)
            if (shaders.len >= 1) {
                shader_stages[stage_count] = createShaderStageCreateInfo(shaders[0], vk.c.VK_SHADER_STAGE_VERTEX_BIT);
                stage_count += 1;
            }
            if (shaders.len >= 2) {
                shader_stages[stage_count] = createShaderStageCreateInfo(shaders[1], vk.c.VK_SHADER_STAGE_FRAGMENT_BIT);
                stage_count += 1;
            }

            config.graphics.create_info.stageCount = stage_count;
            config.graphics.create_info.pStages = &shader_stages;
            config.graphics.create_info.layout = pipeline_layout;

            // TODO: Set renderPass when available
            // config.graphics.create_info.renderPass = render_pass;

            try vk.check(vk.c.vkCreateGraphicsPipelines(device.handle, null, 1, &config.graphics.create_info, null, &pipeline));
        },
    }

    switch (config.*) {
        .compute => {
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
        },
        .graphics => {
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
        },
    }
}

pub fn deinit(self: @This(), device: vk.Device) void {
    vk.c.vkDestroyPipeline(device.handle, self.handle, null);
    vk.c.vkDestroyPipelineLayout(device.handle, self.layout, null);
}

pub fn createComputePipeline(device: vk.Device, shader: vk.c.VkShaderModule, descriptor_layout: vk.c.VkDescriptorSetLayout) !@This() {
    var config = Config.defaultCompute();
    return init(device, &config, descriptor_layout, &.{shader});
}

pub fn createGraphicsPipeline(device: vk.Device, shaders: []const vk.c.VkShaderModule, descriptor_layout: vk.c.VkDescriptorSetLayout) !@This() {
    var config = Config.defaultGraphics();
    return init(device, &config, descriptor_layout, shaders);
}

// Validation functions
pub fn validateConfig(config: *Config, shaders: []const vk.c.VkShaderModule) !void {
    switch (config.*) {
        .compute => {
            if (shaders.len != 1) return error.ComputePipelineRequiresExactlyOneShader;
        },
        .graphics => {
            if (shaders.len == 0) return error.GraphicsPipelineRequiresAtLeastOneShader;

            // Check for vertex shader requirement
            var has_vertex_shader = false;
            var has_fragment_shader = false;

            // Note: In a real implementation, you'd need to inspect shader modules
            // to determine their stages. For now, we assume typical vertex + fragment setup
            if (shaders.len >= 1) has_vertex_shader = true;
            if (shaders.len >= 2) has_fragment_shader = true;

            if (!has_vertex_shader) return error.GraphicsPipelineRequiresVertexShader;
        },
    }
}

pub fn validateGraphicsConfig(graphics: *Config.Graphics) !void {
    // Validate rasterizer settings
    if (graphics.rasterizer.lineWidth <= 0) return error.InvalidLineWidth;

    // Validate depth bounds
    if (graphics.depth_stencil.minDepthBounds < 0 or graphics.depth_stencil.minDepthBounds > 1) {
        return error.InvalidDepthBounds;
    }
    if (graphics.depth_stencil.maxDepthBounds < 0 or graphics.depth_stencil.maxDepthBounds > 1) {
        return error.InvalidDepthBounds;
    }

    // Validate viewport and scissor counts match
    if (graphics.viewport.viewportCount != graphics.viewport.scissorCount) {
        return error.ViewportScissorCountMismatch;
    }
}
