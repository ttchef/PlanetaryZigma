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


fn init(allocator: std.mem.Allocator, vma: vk.Vma, device: vk.Device, file_path: []const u8, TMP_IMAGE: vk.c.VkImage) !@This() {
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
    var materials: std.ArrayList(*vk.Material.Instance) = .empty;

    for (data.images[0..data.samplers_count]) |image| {
        _ = image;
        images.append(allocator, TMP_IMAGE);
    }

    const material_data_buffer: vk.Buffer = .init(vma, @sizeOf(vk.Material.GltfMetallicRoughness) * data.materials_count, vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    const data_index: u32 = 0;

    const scene_material_constans: vk.Material.GltfMetallicRoughness.Constants = .{}; 
    vma.copyToAllocation(
        vk.Material.GltfMetallicRoughness.Constants,
        scene_material_constans,
        materialBuffer.vma_allocation,
        &materialBuffer.info,
    );

    for (data.materials[0..data.materials_count]) |material| {
        var new_material: vk.Material.Instance = .{};

        materials.push_back(newMat);
        file.materials[mat.name.c_str()] = newMat;

        GLTFMetallic_Roughness::MaterialConstants constants;
        constants.colorFactors.x = mat.pbrData.baseColorFactor[0];
        constants.colorFactors.y = mat.pbrData.baseColorFactor[1];
        constants.colorFactors.z = mat.pbrData.baseColorFactor[2];
        constants.colorFactors.w = mat.pbrData.baseColorFactor[3];

        constants.metal_rough_factors.x = mat.pbrData.metallicFactor;
        constants.metal_rough_factors.y = mat.pbrData.roughnessFactor;
        // write material parameters to buffer
        sceneMaterialConstants[data_index] = constants;

        MaterialPass passType = MaterialPass::MainColor;
        if (mat.alphaMode == fastgltf::AlphaMode::Blend) {
            passType = MaterialPass::Transparent;
        }

        GLTFMetallic_Roughness::MaterialResources materialResources;
        // default the material textures
        materialResources.colorImage = engine->_whiteImage;
        materialResources.colorSampler = engine->_defaultSamplerLinear;
        materialResources.metalRoughImage = engine->_whiteImage;
        materialResources.metalRoughSampler = engine->_defaultSamplerLinear;

        // set the uniform buffer for the material data
        materialResources.dataBuffer = file.materialDataBuffer.buffer;
        materialResources.dataBufferOffset = data_index * sizeof(GLTFMetallic_Roughness::MaterialConstants);
        // grab textures from gltf file
        if (mat.pbrData.baseColorTexture.has_value()) {
            size_t img = gltf.textures[mat.pbrData.baseColorTexture.value().textureIndex].imageIndex.value();
            size_t sampler = gltf.textures[mat.pbrData.baseColorTexture.value().textureIndex].samplerIndex.value();

            materialResources.colorImage = images[img];
            materialResources.colorSampler = file.samplers[sampler];
        }
        // build material
        newMat->data = engine->metalRoughMaterial.write_material(engine->_device, passType, materialResources, file.descriptorPool);

        data_index++;
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


