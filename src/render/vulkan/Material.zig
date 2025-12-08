const vk = @import("vulkan");
const nz = @import("numz");
const Image = @import("Image.zig");
const descriptor = @import("descriptor.zig");

const Pass = enum {
    main_color,
    transparent,
    other,
};

const MaterialPipeline = struct {
    pipeline: vk.VkPipeline,
    layout: vk.VkPipelineLayout,
};

pub const Instance = struct {
    pipeline: MaterialPipeline,
    descriptor_set: vk.VkDescriptorSet,
    pass_type: Pass,
};

const GltfMetallicRoughness = struct {
    opaque_pipeline: MaterialPipeline,
    transparent_pipeline: MaterialPipeline,
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

    pub fn buildPipelines() void {}
    pub fn clearResources(device: vk.c.VkDevice) void {}
    pub fn writeMaterial(
        device: vk.c.VkDevice,
        pass: Pass,
        resources: *Resources,
        descriptorAllocator: *descriptor.Growable,
    ) Instance {}
};
