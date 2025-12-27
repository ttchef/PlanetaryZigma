const std = @import("std");
const vk = @import("../vulkan/vulkan.zig");
const cgltf = @import("cgltf");

// storage for all the data on a given glTF file
meshes: std.StringHashMap(*vk.Mesh),
nodes: std.StringHashMap(*vk.Node),
images: std.StringHashMap(vk.Image),
materials: std.StringHashMap(*vk.Material.Instance),

// nodes that dont have a parent, for iterating through the file in tree order
top_nodes: std.ArrayList(*vk.Node),
sampler: std.ArrayList(vk.c.VkSampler),

descriptor_pool: vk.descriptor.Growable,

material_data_buffer: vk.Buffer,

// pub fn clearAll() void {};
//
// pub fn draw(self: *@This(), top_transform: nz.Transform3D(f32), ctx: *DrawContext) void {};
fn extractMagFilter(filter: cgltf.cgltf_filter_type) vk.c.VkFilter  {
    // glTF default magFilter = LINEAR
    if (filter == 0) return vk.c.VK_FILTER_LINEAR;
    return if (filter == cgltf.cgltf_filter_type_nearest) vk.c.VK_FILTER_NEAREST else vk.c.VK_FILTER_LINEAR;
}


fn init(allocator: std.mem.Allocator, device: vk.Device, file_path: []const u8) !@This() {
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


