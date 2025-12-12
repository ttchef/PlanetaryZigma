const vk = @import("vulkan");
const nz = @import("numz");
const Image = @import("Image.zig");
const descriptor = @import("descriptor.zig");
const Mesh = @import("Mesh.zig");
const Device = @import("device.zig").Logical;
const Pipeline = @import("pipeline.zig").Pipeline;

pub const Pass = enum {
    main_color,
    transparent,
    other,
};

pub const Instance = struct {
    pipeline: Pipeline,
    descriptor_set: vk.VkDescriptorSet,
    pass_type: Pass,
};

pub const GltfMetallicRoughness = struct {
    opaque_pipeline: Pipeline,
    transparent_pipeline: Pipeline,
    desctiptor_set_layout: vk.c.VkDescriptorSetLayout,
    writer: descriptor.Writer,

    pub const Constants = struct {
        color_factores: nz.Vec4(f32),
        metal_rough_factors: nz.Vec4(f32),
        //NOTE: padding, we need it anyway for uniform buffers: Source: https://vkguide.dev/docs/new_chapter_4/materials/
        extra: [14]nz.Vec4(f32),
    };

    pub const Resources = struct {
        color_image: Image,
        color_sampler: vk.VkSampler,
        metal_rough_image: Image,
        metal_rough_sampler: vk.VkSampler,
        data_buffer: vk.VkBuffer,
        data_buffer_offset: u32,
    };

    pub fn initBuildPipelines(device: Device, gpu_scene_data_descriptor_layout: vk.c.VkDescriptorSetLayout, draw_image: Image, depth_image: Image) @This() {
        const mesh_frag_shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/mesh.frag.spv");
        const mesh_vertex_shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/mesh.vert.spv");

        const matrixRange: vk.c.VkPushConstantRange = .{
            .offset = 0,
            .size = @sizeOf(Mesh.GPUDrawPushConstants),
            .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
        };

        var material_layout: descriptor.Layout = .init(device, &[_]vk.c.VkDescriptorSetLayout{
            .{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
            .{
                .binding = 1,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
            .{
                .binding = 2,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        });

        var mesh_pipeline_config: Pipeline.Graphics.Config = .{
            .fragment_shaders = .{
                .module = mesh_frag_shader,
            },
            .vertex_shaders = .{
                .module = mesh_vertex_shader,
            },
            .descriptor_set_layouts = &.{
                gpu_scene_data_descriptor_layout.handle,
                material_layout.handle,
            },
            .push_constants = &matrixRange,
        };
        mesh_pipeline_config.render_info.colorAttachmentCount = 1;
        mesh_pipeline_config.render_info.pColorAttachmentFormats = &draw_image.format;
        mesh_pipeline_config.render_info.depthAttachmentFormat = depth_image.format;
        mesh_pipeline_config.enableDepthTesting(vk.c.VK_TRUE, vk.c.VK_COMPARE_OP_GREATER_OR_EQUAL);
        const opaque_pipeline: Pipeline.Graphics = try .init(device, mesh_pipeline_config);

        mesh_pipeline_config.setBlendingDestinationColorBlendFactor(vk.c.VK_BLEND_FACTOR_ONE);
        mesh_pipeline_config.enableDepthTesting(vk.c.VK_FALSE, vk.c.VK_COMPARE_OP_GREATER_OR_EQUAL);
        const transparent_pipeline: Pipeline.Graphics = try .init(device, mesh_pipeline_config);

        return .{
            .opaque_pipeline = opaque_pipeline,
            .transparent_pipeline = transparent_pipeline,
            .descriptor_set_layout = material_layout,
            .writer = .{},
        };
    }

    pub fn deinit(self: *@This(), device: Device) void {
        self.opaque_pipeline.deinit(device);
        self.transparent_pipeline.deinit(device);
        self.desctiptor_set_layout.deinit();
    }

    pub fn writeMaterial(
        self: *@This(),
        device: vk.c.VkDevice,
        pass: Pass,
        resources: *Resources,
        descriptorAllocator: *descriptor.Growable,
    ) Instance {
        var material_data_instance: Instance = undefined;
        material_data_instance.pass_type = pass;
        if (pass == .transparent) {
            material_data_instance.pipeline = &self.transparent_pipeline;
        } else {
            material_data_instance.pipeline = &self.opaque_pipeline;
        }
        material_data_instance.descriptor_set = descriptorAllocator.allocate(device, self.desctiptor_set_layout);
        self.writer.clear();
        self.writer.appendBuffer(0, resources.data_buffer, @sizeOf(Constants), resources.data_buffer_offset, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        self.writer.appendImage(1, resources.color_image.image_view, resources.color_sampler, vk.c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.writer.appendImage(2, resources.metal_rough_image.image_view, resources.metal_rough_sampler, vk.c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        self.writer.updateSet(device, material_data_instance.descriptor_set);
        return material_data_instance;
    }

    // pub fn clearResources(device: vk.c.VkDevice) void {}
};
