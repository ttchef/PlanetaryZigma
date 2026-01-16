const std = @import("std");
const nz = @import("numz");
const vk = @import("../vulkan/vulkan.zig");
const cgltf = @import("cgltf");
const stb = @import("stb");

default_image: vk.Image,
descriptor_pool: vk.descriptor.Growable = undefined,
material_data_buffer: vk.Buffer = undefined,
// storage for all the data on a given glTF file
meshes: std.StringHashMapUnmanaged(*vk.Mesh) = .empty,
nodes: std.StringHashMapUnmanaged(*vk.Node) = .empty,
images: std.StringHashMapUnmanaged(vk.Image) = .empty,
materials: std.StringHashMapUnmanaged(*vk.Material.Instance) = .empty,
// nodes that dont have a parent, for iterating through the file in tree order
top_nodes: std.ArrayList(*vk.Node) = .empty,
samplers: std.ArrayList(vk.c.VkSampler) = .empty,

pub fn init(
    allocator: std.mem.Allocator,
    vma: vk.Vma,
    device: vk.Device,
    file_path: []const u8,
    default_images: [2]vk.Image,
    default_sampler: vk.c.VkSampler,
    metal_rough_material: *vk.Material.GltfMetallicRoughness,
) !@This() {
    std.log.info("Loading GLTF: {s}", .{file_path});
    var file: @This() = .{ .default_image = default_images[0] };

    const options: cgltf.cgltf_options = .{};
    var cptr_data: ?*cgltf.cgltf_data = null;
    defer cgltf.cgltf_free(cptr_data);
    const out_data: [*c][*c]cgltf.cgltf_data = @ptrCast(&cptr_data);

    const c_path = try allocator.dupeZ(u8, file_path); // adds trailing 0
    defer allocator.free(c_path);
    try if (cgltf.cgltf_parse_file(&options, c_path, out_data) != cgltf.cgltf_result_success) error.GltfParse;
    try if (cgltf.cgltf_load_buffers(&options, out_data.*, c_path) != cgltf.cgltf_result_success) error.GltfLoad;
    try if (cgltf.cgltf_validate(out_data.*) != cgltf.cgltf_result_success) error.CltfValidation;
    try if (out_data.? == null or out_data.*.? == null) error.CPointerData;
    var data: cgltf.cgltf_data = out_data.*.*;

    var sizes = [_]vk.descriptor.Growable.PoolSizeRatio{
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .ratio = 3 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 3 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
    };

    file.descriptor_pool = try .init(allocator, device, @intCast(data.materials_count), &sizes);
    if (data.samplers_count != 0) {
        for (data.samplers[0..data.samplers_count]) |sampler| {
            const sampler_info: vk.c.VkSamplerCreateInfo = .{
                .sType = vk.c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
                .maxLod = vk.c.VK_LOD_CLAMP_NONE,
                .minLod = 0,
                .magFilter = extractMagFilter(sampler.mag_filter),
                .minFilter = extractMinFilter(sampler.min_filter),
                .mipmapMode = extract_mipmap_mode(sampler.min_filter),
            };
            var new_sampler: vk.c.VkSampler = undefined;
            try vk.check(vk.c.vkCreateSampler(device.handle, &sampler_info, null, &new_sampler));
            try file.samplers.append(allocator, new_sampler);
        }
    } else {
        std.log.info("Sampler count was 0", .{});
    }

    var images: std.ArrayList(vk.Image) = .empty;
    if (data.images_count != 0) {
        for (data.images[0..data.images_count], 0..data.images_count) |image, i| {
            const img = loadImage(vma, device, image) catch default_images[0];
            try images.append(allocator, img);
            if (image.name != null) {
                const name = std.mem.span(image.name);
                try file.images.put(allocator, name, img);
            } else {
                var buf: [32]u8 = undefined;
                const name = try std.fmt.bufPrint(&buf, "{}", .{i});

                try file.images.put(allocator, name, img);
            }
        }
    } else {
        std.log.info("image count was 0", .{});
    }

    file.material_data_buffer = try .init(vma.handle, @sizeOf(vk.Material.GltfMetallicRoughness) * data.materials_count, vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);
    var data_index: u32 = 0;

    var ptr: [*]vk.Material.GltfMetallicRoughness.Constants = @ptrCast(@alignCast(file.material_data_buffer.info.pMappedData));
    var scene_material_constants = ptr[0..data.materials_count];
    var materials: std.ArrayList(*vk.Material.Instance) = .empty;
    for (data.materials[0..data.materials_count]) |material| {
        const constant: vk.Material.GltfMetallicRoughness.Constants = .{
            .color_factores = material.pbr_metallic_roughness.base_color_factor,
            .metal_rough_factors = .{
                material.pbr_metallic_roughness.metallic_factor,
                material.pbr_metallic_roughness.roughness_factor,
                0,
                0,
            },
        };
        scene_material_constants[data_index] = constant;

        const pass_type: vk.Material.Pass = if (material.alpha_mode == cgltf.cgltf_alpha_mode_blend) vk.Material.Pass.transparent else vk.Material.Pass.main_color;

        var material_resources: vk.Material.GltfMetallicRoughness.Resources = .{
            .color_image = default_images[0],
            .color_sampler = default_sampler,
            .metal_rough_image = default_images[1],
            .metal_rough_sampler = default_sampler,
            .data_buffer = file.material_data_buffer.buffer,
            .data_buffer_offset = data_index * @sizeOf(vk.Material.GltfMetallicRoughness.Constants),
        };

        if (material.pbr_metallic_roughness.base_color_texture.texture != null) {
            const tex = material.pbr_metallic_roughness.base_color_texture.texture.*;
            if (tex.image != null) {
                const img_index = (tex.image - data.images);
                material_resources.color_image = images.items[img_index];
            }
            if (tex.sampler != null) {
                const samp_index = (tex.sampler - data.samplers);
                material_resources.color_sampler = file.samplers.items[samp_index];
            }
        }
        if (material.has_pbr_specular_glossiness != 0) @panic("NOT SUPPORTED");
        const new_material = try allocator.create(vk.Material.Instance);
        new_material.* = try metal_rough_material.writeMaterial(device, pass_type, material_resources, &file.descriptor_pool);
        try materials.append(allocator, new_material);
        try file.materials.put(allocator, std.mem.span(material.name), new_material);
        data_index += 1;
    }

    var meshes: std.ArrayList(*vk.Mesh) = .empty;
    var indices_list: std.ArrayList(u32) = .empty;
    var vertices_list: std.ArrayList(vk.Mesh.Vertex) = .empty;
    defer indices_list.deinit(allocator);
    defer vertices_list.deinit(allocator);
    for (data.meshes[0..data.meshes_count]) |*mesh| {
        indices_list.clearAndFree(allocator);
        vertices_list.clearAndFree(allocator);

        var surfaces: std.ArrayList(vk.Mesh.GeoSurface) = .empty;
        for (mesh.primitives[0..mesh.primitives_count]) |*primitive| {
            const initial_vtx = vertices_list.items.len;
            var idx_acc = if (primitive.indices) |indices| indices.* else continue;
            var pos_acc = if (findAttributeAccessor(primitive, "POSITION")) |position| position.* else continue;

            var new_surface: vk.Mesh.GeoSurface = .{
                .index_start = @intCast(indices_list.items.len),
                .index_count = @intCast(idx_acc.count),
                .material = materials.items[0],
                .bounds = .{
                    .origin = @splat(0),
                    .extents = @splat(0),
                    .sphere_radius = 0,
                },
            };

            try vertices_list.resize(allocator, initial_vtx + pos_acc.count);
            for (0..pos_acc.count) |i| {
                const pos3 = readVec3F32(&pos_acc, i);
                vertices_list.items[initial_vtx + i] = .{
                    .position = pos3,
                    .normal = .{ 1, 0, 0 },
                    .color = .{ 1, 1, 1, 1 },
                    .uv_x = 0,
                    .uv_y = 0,
                };
            }

            try indices_list.ensureTotalCapacity(allocator, indices_list.items.len + idx_acc.count);
            for (0..idx_acc.count) |i| {
                const idx = readIndexU32(&idx_acc, i);
                indices_list.appendAssumeCapacity(idx + @as(u32, @intCast(initial_vtx)));
            }

            if (findAttributeAccessor(primitive, "NORMAL")) |nrm_acc| {
                for (0..nrm_acc.count) |i| {
                    const n3 = readVec3F32(nrm_acc, i);
                    vertices_list.items[initial_vtx + i].normal = n3;
                }
            }

            if (findAttributeAccessor(primitive, "TEXCOORD_0")) |uv_acc| {
                for (0..uv_acc.count) |i| {
                    const uv2 = readVec2UV(uv_acc, i);
                    vertices_list.items[initial_vtx + i].uv_x = uv2[0];
                    vertices_list.items[initial_vtx + i].uv_y = uv2[1];
                }
            }

            if (findAttributeAccessor(primitive, "COLOR_0")) |col_acc| {
                for (0..col_acc.count) |i| {
                    const c4 = readColorVec4(col_acc, i);
                    vertices_list.items[initial_vtx + i].color = c4;
                }
            }

            var min_pos: nz.Vec3(f32) = vertices_list.items[initial_vtx].position;
            var max_pos: nz.Vec3(f32) = vertices_list.items[initial_vtx].position;
            for (initial_vtx..vertices_list.items.len) |i| {
                min_pos = @min(min_pos, @as(nz.Vec3(f32), vertices_list.items[i].position));
                max_pos = @max(max_pos, @as(nz.Vec3(f32), vertices_list.items[i].position));
            }
            const extent = (max_pos - min_pos) / @as(nz.Vec3(f32), .{ 2, 2, 2 });
            new_surface.bounds = .{
                .origin = (max_pos + min_pos) / @as(nz.Vec3(f32), .{ 2, 2, 2 }),
                .extents = extent,
                .sphere_radius = nz.vec.length(extent),
            };

            if (primitive.material != null) {
                const material_idx = primitive.material - data.materials;
                new_surface.material = materials.items[material_idx];
            }
            try surfaces.append(allocator, new_surface);
        }

        var new_mesh = try allocator.create(vk.Mesh);
        new_mesh.* = try .init(device, surfaces, vma.handle, indices_list.items, vertices_list.items);
        new_mesh.name = try allocator.dupe(u8, std.mem.span(mesh.name));
        new_mesh.surfaces = surfaces;
        try meshes.append(allocator, new_mesh);
        try file.meshes.put(allocator, std.mem.span(mesh.name), new_mesh);
    }

    var nodes: std.ArrayList(*vk.Node) = try .initCapacity(allocator, data.nodes_count);
    for (data.nodes[0..data.nodes_count]) |node| {
        var new_node = try allocator.create(vk.Node);
        new_node.* = .{};
        if (node.mesh != null) {
            const mesh_index: usize = @intCast(node.mesh - data.meshes);
            new_node.mesh = meshes.items[mesh_index];
        }

        nodes.appendAssumeCapacity(new_node);

        try file.nodes.put(allocator, std.mem.span(node.name), new_node);

        if (node.has_matrix != 0) {
            const local_matrix: nz.Mat4x4(f32) = .{ .d = node.matrix };
            new_node.local_transform = .fromMat4x4(local_matrix);
        } else {
            const tl: nz.Mat4x4(f32) = .translate(node.translation);
            const rot: nz.Mat4x4(f32) = .fromQuaternion(node.rotation);
            const scale: nz.Mat4x4(f32) = .scale(node.scale);
            new_node.local_transform = .fromMat4x4(scale.mul(rot).mul(tl));
        }
    }

    for (data.nodes[0..data.nodes_count], 0..data.nodes_count) |*node, i| {
        var scene_node = nodes.items[i];
        if (node.children == null) continue;
        for (node.children[0..node.children_count]) |c| {
            const child_index = @as(usize, @intCast(c - data.nodes));
            try scene_node.children.append(allocator, nodes.items[child_index]);
            nodes.items[child_index].parent = scene_node;
        }
    }

    for (nodes.items[0..data.nodes_count]) |node| {
        if (node.parent == null) {
            try file.top_nodes.append(allocator, node);
            var top_transform: nz.Transform3D(f32) = .{};
            node.refreshTransform(&top_transform);
        }
    }

    return file;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator, vma: vk.Vma, device: vk.Device) void {
    self.descriptor_pool.deinit(device);
    self.material_data_buffer.deinit(vma.handle);

    var mesh_it = self.meshes.iterator();
    while (mesh_it.next()) |mesh| {
        mesh.value_ptr.*.deinit(vma.handle);
    }

    var images_it = self.images.iterator();
    while (images_it.next()) |image| {
        if (image.value_ptr.vk_image == self.default_image.vk_image) continue;
        image.value_ptr.deinit(vma, device);
    }

    for (self.samplers.items) |sampler| {
        vk.c.vkDestroySampler(device.handle, sampler, null);
    }

    self.meshes.deinit(allocator);
    self.nodes.deinit(allocator);
    self.images.deinit(allocator);
    self.materials.deinit(allocator);
    self.top_nodes.deinit(allocator);
    self.samplers.deinit(allocator);
}

pub fn draw(self: *@This(), allocator: std.mem.Allocator, top_transform: nz.Transform3D(f32), ctx: *vk.Node.DrawContext) !void {
    for (self.top_nodes.items) |node| {
        try node.draw(allocator, top_transform, ctx);
    }
}

fn extractMagFilter(filter: cgltf.cgltf_filter_type) vk.c.VkFilter {
    // glTF default magFilter = LINEAR
    if (filter == 0) return vk.c.VK_FILTER_LINEAR;
    return if (filter == cgltf.cgltf_filter_type_nearest) vk.c.VK_FILTER_NEAREST else vk.c.VK_FILTER_LINEAR;
}

fn readU16LE(p: [*]const u8) u16 {
    return std.mem.readInt(u16, p[0..2], .little);
}

fn readU32LE(p: [*]const u8) u32 {
    return std.mem.readInt(u32, p[0..4], .little);
}

fn readF32LE(p: [*]const u8) f32 {
    const bits = readU32LE(p);
    return @bitCast(bits);
}

fn findAttributeAccessor(prim: *cgltf.cgltf_primitive, name: []const u8) ?*cgltf.cgltf_accessor {
    for (prim.attributes[0..prim.attributes_count]) |attribute| {
        if (std.mem.eql(u8, std.mem.span(attribute.name), name)) return attribute.data;
    }
    return null;
}

fn accessorBasePtr(acc: *const cgltf.cgltf_accessor) [*]const u8 {
    const bv: *const cgltf.cgltf_buffer_view = acc.*.buffer_view;
    const buf: *const cgltf.cgltf_buffer = bv.*.buffer;
    const buf_data: [*]const u8 = @ptrCast(buf.*.data);
    const off: usize = bv.*.offset + acc.*.offset;
    return buf_data + off;
}

fn accessorStride(acc: *const cgltf.cgltf_accessor) usize {
    if (acc.*.stride != 0) return @as(usize, @intCast(acc.*.stride));
    const cs = cgltf.cgltf_component_size(acc.*.component_type);
    const nc = cgltf.cgltf_num_components(acc.*.type);
    return cs * nc;
}

fn readVec2F32(acc: *const cgltf.cgltf_accessor, index: usize) [2]f32 {
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;
    return .{ readF32LE(p + 0), readF32LE(p + 4) };
}

fn readVec3F32(acc: *const cgltf.cgltf_accessor, index: usize) [3]f32 {
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;
    return .{ readF32LE(p + 0), readF32LE(p + 4), readF32LE(p + 8) };
}

fn readColorVec4(acc: *const cgltf.cgltf_accessor, index: usize) [4]f32 {
    // COLOR_0 can be VEC3 or VEC4
    // component can be f32 or normalized u8/u16 (very common)
    // If unknown, returns white.
    const comps: usize = cgltf.cgltf_component_size(acc.*.type);
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;

    var out: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 };

    switch (acc.*.component_type) {
        cgltf.cgltf_component_type_r_32f => {
            // read comps floats
            var i: usize = 0;
            while (i < comps and i < 4) : (i += 1) {
                out[i] = readF32LE(p + i * 4);
            }
            if (comps == 3) out[3] = 1.0;
            return out;
        },
        cgltf.cgltf_component_type_r_8u => {
            if (acc.*.normalized == 0) return out; // non-normalized colors are unusual; ignore
            var i: usize = 0;
            while (i < comps and i < 4) : (i += 1) {
                const u: u8 = p[i];
                out[i] = @as(f32, @floatFromInt(u)) / 255.0;
            }
            if (comps == 3) out[3] = 1.0;
            return out;
        },
        cgltf.cgltf_component_type_r_16u => {
            if (acc.*.normalized == 0) return out;
            var i: usize = 0;
            while (i < comps and i < 4) : (i += 1) {
                const u: u16 = readU16LE(p + i * 2);
                out[i] = @as(f32, @floatFromInt(u)) / 65535.0;
            }
            if (comps == 3) out[3] = 1.0;
            return out;
        },
        else => return out,
    }
}

fn readIndexU32(acc: *const cgltf.cgltf_accessor, index: usize) u32 {
    // Indices accessor: component_type should be r_8u / r_16u / r_32u
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;

    return switch (acc.*.component_type) {
        cgltf.cgltf_component_type_r_8u => @as(u32, p[0]),
        cgltf.cgltf_component_type_r_16u => @as(u32, readU16LE(p)),
        cgltf.cgltf_component_type_r_32u => readU32LE(p),
        else => 0,
    };
}

// ---- optional: TEXCOORD_0 reader that also supports normalized u16 ----
// (fastgltf auto-converted this; cgltf will not.)
fn readVec2UV(acc: *const cgltf.cgltf_accessor, index: usize) [2]f32 {
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;

    switch (acc.*.component_type) {
        cgltf.cgltf_component_type_r_32f => return .{ readF32LE(p + 0), readF32LE(p + 4) },
        cgltf.cgltf_component_type_r_16u => {
            if (acc.*.normalized == 0) return .{ 0, 0 };
            const first = readU16LE(p + 0);
            const second = readU16LE(p + 2);
            return .{
                @as(f32, @floatFromInt(first)) / 65535.0,
                @as(f32, @floatFromInt(second)) / 65535.0,
            };
        },
        else => return .{ 0, 0 },
    }
}

fn extractMinFilter(filter: cgltf.cgltf_filter_type) vk.c.VkFilter {
    // glTF default minFilter = LINEAR_MIPMAP_LINEAR
    if (filter == 0) return vk.c.VK_FILTER_LINEAR;
    switch (filter) {
        cgltf.cgltf_filter_type_nearest, cgltf.cgltf_filter_type_nearest_mipmap_nearest, cgltf.cgltf_filter_type_nearest_mipmap_linear => return vk.c.VK_FILTER_NEAREST,
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

pub fn loadImage(vma: vk.Vma, device: vk.Device, image: cgltf.cgltf_image) !vk.Image {
    var width: i32, var height: i32, var nr_channel: i32 = .{ 0, 0, 0 };

    if (image.uri != null and image.uri[0] != 0) {
        try if (std.mem.eql(u8, "data:", std.mem.span(image.uri)[0..5])) error.DataNotsupported;

        const pixels = stb.stbi_load(image.uri, &width, &height, &nr_channel, 4);
        defer stb.stbi_image_free(pixels);
        try if (pixels == null) error.LoadingStbi;
        const extent: vk.c.VkExtent3D = .{ .width = @intCast(width), .height = @intCast(height), .depth = 1 };

        var out_image: vk.Image = try .init(
            vma.handle,
            device,
            vk.c.VK_FORMAT_R8G8B8A8_UNORM,
            extent,
            vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
            true,
        );

        out_image.extent = extent;
        try out_image.uploadDataToImage(device, vma.handle, pixels);
        return out_image;
    } else if (image.buffer_view != null) {
        const bv = image.buffer_view;
        const buf = bv.*.buffer;
        try if (buf == null or buf.*.data == null) error.BufferView;

        const bytes: [*]const u8 = @ptrCast(buf.*.data);
        const bytes_offset = bytes[bv.*.offset .. bv.*.offset + bv.*.size];

        const pixels = stb.stbi_load_from_memory(bytes_offset.ptr, @intCast(bytes_offset.len), &width, &height, &nr_channel, 4);
        defer stb.stbi_image_free(pixels);
        try if (pixels == null) error.LoadingStbi;
        const extent: vk.c.VkExtent3D = .{ .width = @intCast(width), .height = @intCast(height), .depth = 1 };
        var out_image: vk.Image = try .init(
            vma.handle,
            device,
            vk.c.VK_FORMAT_R8G8B8A8_UNORM,
            extent,
            vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
            vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
            true,
        );

        try out_image.uploadDataToImage(device, vma.handle, pixels);
        return out_image;
    }
    return error.loadImage;
}
