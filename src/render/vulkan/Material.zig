const vk = @import("vulkan");
const nz = @import("numz");
const Image = @import("Image.zig");
const descriptor = @import("descriptor.zig");
const Mesh = @import("Mesh.zig");
const Device = @import("device.zig").Logical;
const Pipeline = @import("pipeline.zig").Pipeline;

const Pass = enum {
    main_color,
    transparent,
    other,
};

pub const Instance = struct {
    pipeline: Pipeline,
    descriptor_set: vk.VkDescriptorSet,
    pass_type: Pass,
};

const GltfMetallicRoughness = struct {
    opaque_pipeline: Pipeline,
    transparent_pipeline: Pipeline,
    desctiptor_set_layout: vk.c.VkDescriptorSetLayout,
    writer: descriptor.Writer,

    const Constants = struct {
        color_factores: nz.Vec4(f32),
        metal_rough_factors: nz.Vec4(f32),
        //NOTE: padding, we need it anyway for uniform buffers: Source: https://vkguide.dev/docs/new_chapter_4/materials/
        extra: [14]nz.Vec4(f32),
    };

    const Resources = struct {
        color_image: Image,
        color_sampler: vk.VkSampler,
        metal_rough_image: Image,
        metal_rough_sampler: vk.VkSampler,
        data_buffer: vk.VkBuffer,
        data_buffer_offset: u32,
    };

    // pub fn buildPipelines(device: Device, gpu_scene_data_descriptor_layout: vk.c.VkDescriptorSetLayout) void {
    //     const meshFragShader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/mesh.frag.spv");
    //
    //     const meshVertexShader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/mesh.vert.spv");
    //
    //     const matrixRange: vk.c.VkPushConstantRange = .{
    //         .offset = 0,
    //         .size = @sizeOf(Mesh.GPUDrawPushConstants),
    //         .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
    //     };
    //
    //     var material_layout: descriptor.Layout = .init(device, &[_]vk.c.VkDescriptorSetLayout{
    //         .{
    //             .binding = 0,
    //             .descriptorCount = 1,
    //             .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    //             .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
    //         },
    //         .{
    //             .binding = 1,
    //             .descriptorCount = 1,
    //             .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    //             .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
    //         },
    //         .{
    //             .binding = 2,
    //             .descriptorCount = 1,
    //             .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    //             .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
    //         },
    //     });
    //
    //     var mesh_pipeline_config: Pipeline.Graphics.Config = .{
    //             .descriptor_set_layouts = &.{
    //                 gpu_scene_data_descriptor_layout.handle,
    //                 material_layout.handle,
    //             },
    //             .push_constants = &matrixRange,
    //         };
    //
    //     var pipeline: Pipeline.Graphics = try .init(device, mesh_pipeline_config);
    //
    //
    //
    // PipelineBuilder pipelineBuilder;
    // pipelineBuilder.set_shaders(meshVertexShader, meshFragShader);
    // pipelineBuilder.set_input_topology(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    // pipelineBuilder.set_polygon_mode(VK_POLYGON_MODE_FILL);
    // pipelineBuilder.set_cull_mode(VK_CULL_MODE_NONE, VK_FRONT_FACE_CLOCKWISE);
    // pipelineBuilder.set_multisampling_none();
    // pipelineBuilder.disable_blending();
    // pipelineBuilder.enable_depthtest(true, VK_COMPARE_OP_GREATER_OR_EQUAL);
    //
    // //render format
    // pipelineBuilder.set_color_attachment_format(engine->_drawImage.imageFormat);
    // pipelineBuilder.set_depth_format(engine->_depthImage.imageFormat);
    //
    // // use the triangle layout we created
    // pipelineBuilder._pipelineLayout = newLayout;
    //
    // // finally build the pipeline
    //    opaquePipeline.pipeline = pipelineBuilder.build_pipeline(engine->_device);
    //
    // // create the transparent variant
    // pipelineBuilder.enable_blending_additive();
    //
    // pipelineBuilder.enable_depthtest(false, VK_COMPARE_OP_GREATER_OR_EQUAL);
    //
    // transparentPipeline.pipeline = pipelineBuilder.build_pipeline(engine->_device);
    //
    // vkDestroyShaderModule(engine->_device, meshFragShader, nullptr);
    // vkDestroyShaderModule(engine->_device, meshVertexShader, nullptr);
    //    }
    //
    //    pub fn clearResources(device: vk.c.VkDevice) void {}
    //    pub fn writeMaterial(
    //        device: vk.c.VkDevice,
    //        pass: Pass,
    //        resources: *Resources,
    //        descriptorAllocator: *descriptor.Growable,
    //    ) Instance {}
};
