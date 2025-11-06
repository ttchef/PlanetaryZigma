const std = @import("std");
const vk = @import("vulkan.zig");
const nz = @import("numz");

pub const Pipeline = union(enum) {
    compute: Compute,
    graphics: Graphics,

    pub const Shader = struct {
        module: vk.c.VkShaderModule,
        entry_name: ?[*:0]const u8 = null,
        specialization: [*c]const vk.c.VkSpecializationInfo = null,
    };

    pub const Compute = struct {
        handle: vk.c.VkPipeline,
        layout: vk.c.VkPipelineLayout,
        data: PushConstant,

        pub const PushConstant = struct {
            data1: nz.Vec4(f32) = @splat(0),
            data2: nz.Vec4(f32) = @splat(0),
            data3: nz.Vec4(f32) = @splat(0),
            data4: nz.Vec4(f32) = @splat(0),
        };

        pub const Config = struct {
            shader: Shader,
            descriptor_set_layouts: []const vk.c.VkDescriptorSetLayout,
        };

        pub fn init(device: vk.Device, config: *Config) !@This() {
            var layout_create_info: vk.c.VkPipelineLayoutCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .pSetLayouts = @ptrCast(config.descriptor_set_layouts),
                .setLayoutCount = @intCast(config.descriptor_set_layouts.len),
                .pPushConstantRanges = &.{
                    .offset = 0,
                    .size = @sizeOf(PushConstant),
                    .stageFlags = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
                },
                .pushConstantRangeCount = 1,
            };

            var layout: vk.c.VkPipelineLayout = undefined;
            try vk.check(vk.c.vkCreatePipelineLayout(device.handle, &layout_create_info, null, &layout));

            var pipeline_create_info: vk.c.VkComputePipelineCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
                .stage = .{
                    .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
                    .module = config.shader.module,
                    .pName = config.shader.entry_name orelse "main",
                    .pSpecializationInfo = config.shader.specialization,
                },
                .layout = layout,
                .basePipelineHandle = null,
                .basePipelineIndex = -1,
            };

            var pipeline: vk.c.VkPipeline = undefined;
            try vk.check(vk.c.vkCreateComputePipelines(device.handle, null, 1, &pipeline_create_info, null, &pipeline));
            return .{
                .handle = pipeline,
                .layout = layout,
                .data = .{},
            };
        }
    };

    pub const Graphics = struct {
        handle: vk.c.VkPipeline,
        layout: vk.c.VkPipelineLayout,

        pub const Config = struct {
            vertex_shaders: Shader,
            fragment_shaders: Shader,

            descriptor_set_layouts: []const vk.c.VkDescriptorSetLayout,
            push_constants: []const vk.c.VkPushConstantRange,

            vertex_input_state: vk.c.VkPipelineVertexInputStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .vertexBindingDescriptionCount = 0,
                .pVertexBindingDescriptions = null,
                .vertexAttributeDescriptionCount = 0,
                .pVertexAttributeDescriptions = null,
            },
            input_assembly_state: vk.c.VkPipelineInputAssemblyStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .topology = vk.c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = 0,
            },
            tessellation_state: vk.c.VkPipelineTessellationStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO,
            },
            viewport_state: vk.c.VkPipelineViewportStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            },
            rasterization_state: vk.c.VkPipelineRasterizationStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .polygonMode = vk.c.VK_POLYGON_MODE_FILL,
                .cullMode = vk.c.VK_CULL_MODE_BACK_BIT,
                .frontFace = vk.c.VK_FRONT_FACE_CLOCKWISE,
                .lineWidth = 1.0,
            },
            multisample_state: vk.c.VkPipelineMultisampleStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .rasterizationSamples = vk.c.VK_SAMPLE_COUNT_1_BIT,
            },
            depth_stencil_state: vk.c.VkPipelineDepthStencilStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            },
            color_blend_state: vk.c.VkPipelineColorBlendStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .logicOpEnable = 0,
                .attachmentCount = 0,
                .pAttachments = null,
            },
            dynamic_state: vk.c.VkPipelineDynamicStateCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            },
            render_info: vk.c.VkPipelineRenderingCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            },
            base_pipeline_handle: vk.c.VkPipeline = null,
            base_pipeline_index: i32 = -1,

            pub fn enableDepthTesting(self: *@This(), depth_write_enable: u32, op: vk.c.VkCompareOp) void {
                self.depth_stencil_state.depthTestEnable = vk.c.VK_TRUE;
                self.depth_stencil_state.depthWriteEnable = depth_write_enable;
                self.depth_stencil_state.depthCompareOp = op;
                self.depth_stencil_state.depthBoundsTestEnable = vk.c.VK_FALSE;
                self.depth_stencil_state.stencilTestEnable = vk.c.VK_FALSE;
                // self.depth_stencil_state.front = {};
                // self.depth_stencil_state.back = {};
                self.depth_stencil_state.minDepthBounds = 0;
                self.depth_stencil_state.maxDepthBounds = 1;
            }
        };

        pub fn init(device: vk.Device, config: *Config) !@This() {
            var layout_create_info: vk.c.VkPipelineLayoutCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .pSetLayouts = @ptrCast(config.descriptor_set_layouts),
                .setLayoutCount = @intCast(config.descriptor_set_layouts.len),
                .pPushConstantRanges = @ptrCast(config.push_constants),
                .pushConstantRangeCount = @intCast(config.push_constants.len),
            };

            var layout: vk.c.VkPipelineLayout = undefined;
            try vk.check(vk.c.vkCreatePipelineLayout(device.handle, &layout_create_info, null, &layout));

            var shader_stages: [2]vk.c.VkPipelineShaderStageCreateInfo = .{
                .{
                    .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
                    .module = config.vertex_shaders.module,
                    .pName = config.vertex_shaders.entry_name orelse "main",
                    .pSpecializationInfo = config.vertex_shaders.specialization,
                },
                .{
                    .sType = vk.c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                    .stage = vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
                    .module = config.fragment_shaders.module,
                    .pName = config.fragment_shaders.entry_name orelse "main",
                    .pSpecializationInfo = config.fragment_shaders.specialization,
                },
            };

            var pipeline_create_info: vk.c.VkGraphicsPipelineCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                .pNext = &config.render_info,
                .stageCount = 2,
                .pStages = &shader_stages,
                .layout = layout,
                .pVertexInputState = &config.vertex_input_state,
                .pInputAssemblyState = &config.input_assembly_state,
                .pTessellationState = &config.tessellation_state,
                .pViewportState = &config.viewport_state,
                .pRasterizationState = &config.rasterization_state,
                .pMultisampleState = &config.multisample_state,
                .pDepthStencilState = &config.depth_stencil_state,
                .pColorBlendState = &config.color_blend_state,
                .pDynamicState = &config.dynamic_state,
                .basePipelineHandle = config.base_pipeline_handle,
                .basePipelineIndex = config.base_pipeline_index,
            };

            var pipeline: vk.c.VkPipeline = undefined;
            try vk.check(vk.c.vkCreateGraphicsPipelines(device.handle, null, 1, &pipeline_create_info, null, &pipeline));
            return .{
                .handle = pipeline,
                .layout = layout,
            };
        }
    };

    pub fn initCompute(device: vk.Device, config: *Compute.Config) !@This() {
        return .{ .compute = try .init(device, config) };
    }

    pub fn initGraphics(device: vk.Device, config: *Graphics.Config) !@This() {
        return .{ .graphics = try .init(device, config) };
    }

    pub fn deinit(self: @This(), device: vk.Device) void {
        vk.c.vkDestroyPipelineLayout(device.handle, self.get().layout, null);
        vk.c.vkDestroyPipeline(device.handle, self.get().handle, null);
    }

    pub fn get(self: @This()) struct { handle: vk.c.VkPipeline, layout: vk.c.VkPipelineLayout } {
        return switch (self) {
            inline else => |pipeline| .{ .handle = pipeline.handle, .layout = pipeline.layout },
        };
    }
};
