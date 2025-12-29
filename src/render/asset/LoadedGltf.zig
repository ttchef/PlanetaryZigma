const std = @import("std");
const vk = @import("../vulkan/vulkan.zig");
const cgltf = @import("cgltf");

// storage for all the data on a given glTF file
meshes: std.StringHashMap(*vk.Mesh) = .empty,
nodes: std.StringHashMap(*vk.Node) = .empty,
images: std.StringHashMap(vk.Image) = .empty,
materials: std.StringHashMap(*vk.Material.Instance) = .empty,

// nodes that dont have a parent, for iterating through the file in tree order
top_nodes: std.ArrayList(*vk.Node) = .empty,
sampler: std.ArrayList(vk.c.VkSampler) = .empty,

descriptor_pool: vk.descriptor.Growable = undefined,

material_data_buffer: vk.Buffer = undefined,

// pub fn clearAll() void {};
//
// pub fn draw(self: *@This(), top_transform: nz.Transform3D(f32), ctx: *DrawContext) void {};
fn extractMagFilter(filter: cgltf.cgltf_filter_type) vk.c.VkFilter  {
    // glTF default magFilter = LINEAR
    if (filter == 0) return vk.c.VK_FILTER_LINEAR;
    return if (filter == cgltf.cgltf_filter_type_nearest) vk.c.VK_FILTER_NEAREST else vk.c.VK_FILTER_LINEAR;
}


fn init(allocator: std.mem.Allocator, vma: vk.Vma, device: vk.Device, file_path: []const u8, TMP_IMAGES: [3]vk.c.VkImage, TMP_SAMPLER: [2]vk.c.VkSampler, metal_rough_material: *vk.Material.GltfMetallicRoughness) !@This() {
    std.log.info("Loading GLTF: {s}", .{filePath});

    const options: cgltf.cgltf_options = .{};
    const data: cgltf.cgltf_data = .{};

    if (cgltf.cgltf_parse_file(&options, file_path, &data) != cgltf.cgltf_result_success) error.GltfParse;
    if (cgltf.cgltf_load_buffers(&options, data, file_path) != cgltf.cgltf_result_success) error.GltfLoad;
    if (cgltf.cgltf_validate(data) != cgltf.cgltf_result_success) error.CltfValidation;


    var sizes = [_]vk.descriptor.Growable.PoolSizeRatio{
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 3 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
    };

    var descriptor_allocator: vk.descriptor.Growable = try .init(allocator, device, data.materials_count, &sizes);

    var samplers: std.ArrayList(vk.c.VkSampler) = .empty;
    for (data.samplers[0..data.samplers_count]) |sampler| {
        const sampler_info: vk.c.VkSamplerCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
            .maxLoad = vk.c.VK_LOD_CLAMP_NONE,
            .minLoad = 0,
            .magFilter = extractMagFilter(sampler.mag_filter),
            .minFilter = extractMinFilter(sampler.min_filter),
            .mipmapMode = extract_mipmap_mode(sampler.min_filter),
        };
        var new_sampler: vk.c.VkSampler = undefined;
        vk.c.vkCreateSampler(device.handle, &sampler_info, null, new_sampler);
        samplers.append(allocator, new_sampler);
    }
    var meshes: std.ArrayList(*vk.Mesh) = .empty;
    var nodes: std.ArrayList(*vk.Node) = .empty;
    var images: std.ArrayList(vk.Image) = .empty;
    var materials: std.StringHashMapUnmanaged(vk.Material.Instance) = .empty;

    for (data.images[0..data.samplers_count]) |image| {
        _ = image;
        images.append(allocator, TMP_IMAGE[0]);
    }

    const material_data_buffer: vk.Buffer = .init(vma, @sizeOf(vk.Material.GltfMetallicRoughness) * data.materials_count, vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    const data_index: u32 = 0;

    var scene_material_constans: vk.Material.GltfMetallicRoughness.Constants = .{}; 
    vma.copyToAllocation(
        vk.Material.GltfMetallicRoughness.Constants,
        scene_material_constans,
        materialBuffer.vma_allocation,
        &materialBuffer.info,
    );

    for (data.materials[0..data.materials_count]) |material| {
        const constant: vk.Material.GltfMetallicRoughness.Constants = .{
            .color_factores = .{
                .x = material.pbr_metallic_roughness.base_color_factor[0],
                .y = material.pbr_metallic_roughness.base_color_factor[1],
                .z = material.pbr_metallic_roughness.base_color_factor[2],
                .w = material.pbr_metallic_roughness.base_color_factor[3],
            },
            .metal_rough_factors = .{
                .x = material.pbr_metallic_roughness.metallic_factor,
                .y = material.pbr_metallic_roughness.roughness_factor,
            },
        };
        scene_material_constans[data_index] = constant;

        const pass_type: vk.Material.Pass = if(material.alpha_mode == cgltf.cgltf_alpha_mode_blend) vk.Material.Pass.transparent
            else vk.Material.Pass.main_color;

        var material_resources: vk.Material.GltfMetallicRoughness.Resources = .{
            .color_image = TMP_IMAGES[1],
            .color_sampler = TMP_SAMPLER[0],
            .metal_rough_image = TMP_IMAGES[2],
            .metal_rough_sampler = TMP_IMAGES[1],
            .data_buffer = material_data_buffer,
            .data_buffer_offset = data_index * @sizeOf(vk.Material.GltfMetallicRoughness.Constants),
        };

        if (material.pbr_metallic_roughness.base_color_texture.texture) {
            const tex= material.pbr_metallic_roughness.base_color_texture.texture.*;
            if (tex.image) {
                //TODO: FIX Pointer subtraction
                const img_index = (tex.image - data.images);
                material_resources.color_image = images[img_index];
            }
            if (tex.sampler) {
                //TODO: FIX Pointer subtraction
                const samp_index = (tex.sampler - data.samplers);
                material_resources.color_sampler = samplers[samp_index];
            }
        }
        materials.put(allocator, material.name, metal_rough_material.writeMaterial(device, pass_type, material_resources, descriptor_allocator));
        data_index += 1;
    }

    return .{
        
    }
}

fn extractMinFilter(filter: cgltf.cgltf_filter_type) vk.c.VkFilter  {
    // glTF default minFilter = LINEAR_MIPMAP_LINEAR
    if (filter == 0) return vk.c.VK_FILTER_LINEAR;
    switch (filter) {
        cgltf.cgltf_filter_type_nearest,
        cgltf.cgltf_filter_type_nearest_mipmap_nearest,
        cgltf.cgltf_filter_type_nearest_mipmap_linear
        => return vk.c.VK_FILTER_NEAREST,
    else => return vk.c.VK_FILTER_LINEAR,
    }
}


fn extract_mipmap_mode(filter: cgltf.cgltf_filter_type) vk.c.VkSamplerMipmapMode {
    switch (filter) {
        cgltf.cgltf_filter_type_nearest_mipmap_nearest,
        cgltf.cgltf_filter_type_linear_mipmap_nearest,
        => return vk.c.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        else => return vk.c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        //NOTE: exist more
        //case fastgltf::Filter::NearestMipMapLinear:
        //case fastgltf::Filter::LinearMipMapLinear:

    }
}


