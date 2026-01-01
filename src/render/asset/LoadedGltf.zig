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

fn readU16LE(p: [*]const u8) u16 {
    return std.mem.readIntLittle(u16, p[0..2]);
}

fn readU32LE(p: [*]const u8) u32 {
    return std.mem.readIntLittle(u32, p[0..4]);
}

fn readF32LE(p: [*]const u8) f32 {
    const bits = readU32LE(p);
    return @bitCast(f32, bits);
}

fn findAttributeAccessor(prim: *cgltf.cgltf_primitive, name: []const u8) ?*cgltf.cgltf_accessor{
    for (prim.attributes[0..prim.attributes_count]) |attribute|{
       if (std.mem.eql(u8, attribute.name, name)) return attribute.data;
    }
    return null;
}

pub fn accessorBasePtr(acc: *const cgltf.cgltf_accessor) [*]const u8 {
    const bv: *const cgltf.cgltf_buffer_view = acc.*.buffer_view ;
    const buf: *const cgltf.cgltf_buffer = bv.*.buffer;
    const buf_data: [*]const u8 = @ptrCast([*]const u8, buf.*.data);
    const off: usize = bv.*.offset + acc.*.offset;
    return buf_data + off;
}


pub fn accessorStride(acc: *const cgl_cgltf.cgltf_accessor) usize {
    if (acc.*.stride != 0) return @as(usize, @intCast(acc.*.stride));
    const cs = cgltf.cgltf_component_size(acc.*.component_type);
    const nc = cgltf.cgltf_num_components(acc.*.type);
    return cs * nc;
}

pub fn readVec2F32(acc: *const cgl_cgltf.cgltf_accessor, index: usize) [2]f32 {
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;
    return .{ readF32LE(p + 0), readF32LE(p + 4) };
}

pub fn readVec3F32(acc: *const cgl_cgltf.cgltf_accessor, index: usize) [3]f32 {
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;
    return .{ readF32LE(p + 0), readF32LE(p + 4), readF32LE(p + 8) };
}

pub fn readColorVec4(acc: *const cgltf.cgltf_accessor, index: usize) [4]f32 {
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

pub fn readIndexU32(acc: *const cgltf.cgltf_accessor, index: usize) u32 {
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
pub fn readVec2UV(acc: *const cgltf.cgltf_accessor, index: usize) [2]f32 {
    const base = accessorBasePtr(acc);
    const stride = accessorStride(acc);
    const p = base + index * stride;

    switch (acc.*.component_type) {
        cgltf.cgltf_component_type_r_32f => return .{ readF32LE(p + 0), readF32LE(p + 4) },
        cgltf.cgltf_component_type_r_16u => {
            if (acc.*.normalized == 0) return .{ 0, 0 };
            const u0 = readU16LE(p + 0);
            const u1 = readU16LE(p + 2);
            return .{
                @as(f32, @floatFromInt(u0)) / 65535.0,
                @as(f32, @floatFromInt(u1)) / 65535.0,
            };
        },
        else => return .{ 0, 0 },
    }
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

    //NOTE: MESH LAODING move to another place?
    var indecies_list: std.ArrayList(u32) = .empty;
    var vertices_list: std.ArrayList(vk.Mesh.Vertex) = .empty;
    defer indecies_list.deinit(allocator);
    defer vertices_list.deinit(allocator);

    for (data.meshes[0..data.meshes_count]) |mesh| {
        //TODO : MOVE TO END
        //std::shared_ptr<MeshAsset> newmesh = std::make_shared<MeshAsset>();
        // meshes.push_back(newmesh);
        // file.meshes[mesh.name.c_str()] = newmesh;
        // newmesh->name = mesh.name;

        indecies_list.clearAndFree(allocator);
        vertices_list.clearAndFree(allocator);


        for (mesh.primitives[0..mesh.primitives_count]) |primitive|{
            //TODO:surface mesh
            // GeoSurface newSurface;
            // var new_mesh: vk.Mesh =
            // newSurface.startIndex = (uint32_t)indices.size();
            // newSurface.count = (uint32_t)gltf.accessors[p.indicesAccessor.value()].count;

            var initial_vtx = vertices_list.items.len;
            var idx_acc = primitive.indices;
            if (!idx_acc) continue;

            var pos_acc = findAttributeAccessor(primitive, "POSITION");
            if (!pos_acc) continue;

            vertices_list.resize(allocator, initial_vtx + pos_acc.?.count);
            for (0..pos_acc.?.count) |i|{
                const pos3 = readVec3F32(pos_acc, i);
                // var v:  vk.Mesh.Vertex  =
                vertices_list.items[initial_vtx + i] = .{
                    .position = pos3,
                    .normal = .{1,0,0},
                    .color = .{1,1,1,1},
                    .uv_x = 0,
                    .uv_y = 0,
                };
            }

            indecies_list.resize(allocator,  indecies_list.items.len + idx_acc.?.count);
            for (0..idx_acc.?.count) |i| {
                const idx = readIndexU32(idx_acc, i);
                indecies_list.appendAssumeCapacity(idx + initial_vtx);
            }

            var nrm_acc = findAttributeAccessor(primitive, "NORMAL");
            if (nrm_acc) {
                for (0..nrm_acc.count)|i|{
                    const n3 = readVec3F32(nrm_acc, i);
                    vertices_list.items[initial_vtx + i].normal = n3;
                }
            }

            var uv_acc = findAttributeAccessor(primitive, "TEXCOORD_0");
            if (uv_acc) {
                for (0..uv_acc.count) |i| {
                     const uv2 = readVec2UV(uv_acc, i);
                    vertices_list.items[initial_vtx + i].uv_x = uv2[0];
                    vertices_list.items[initial_vtx + i].uv_y = uv2[1];
                }
            }

            var col_acc = findAttributeAccessor(primitive, "COLOR_0");
            if (col_acc){
                const c4 = readColorVec4(col_acc, i);
                vertices_list.items[initial_vtx + i].color = c4;
            }

            if (primitive.material) {
                const material_idx = primitive.material - data.materials;

            }
            //TODO: think about it. how do we donnect this with out Implmenation
            // if (p.materialIndex.has_value()) {
            //     newSurface.material = materials[p.materialIndex.value()];
            // } else {
            //     newSurface.material = materials[0];
            // }
            //
            // newmesh->surfaces.push_back(newSurface);
        }
        
        //TODO: Move UploadMesh to a new place?
        //newmesh->meshBuffers = engine->uploadMesh(indices, vertices);
    }

    // load all nodes and their meshes
    for (fastgltf::Node& node : gltf.nodes) {
        std::shared_ptr<Node> newNode;

        // find if the node has a mesh, and if it does hook it to the mesh pointer and allocate it with the meshnode class
        if (node.meshIndex.has_value()) {
            newNode = std::make_shared<MeshNode>();
            static_cast<MeshNode*>(newNode.get())->mesh = meshes[*node.meshIndex];
        } else {
            newNode = std::make_shared<Node>();
        }

        nodes.push_back(newNode);
        file.nodes[node.name.c_str()];

        std::visit(fastgltf::visitor { [&](fastgltf::Node::TransformMatrix matrix) {
                                          memcpy(&newNode->localTransform, matrix.data(), sizeof(matrix));
                                      },
                       [&](fastgltf::Node::TRS transform) {
                           glm::vec3 tl(transform.translation[0], transform.translation[1],
                               transform.translation[2]);
                           glm::quat rot(transform.rotation[3], transform.rotation[0], transform.rotation[1],
                               transform.rotation[2]);
                           glm::vec3 sc(transform.scale[0], transform.scale[1], transform.scale[2]);

                           glm::mat4 tm = glm::translate(glm::mat4(1.f), tl);
                           glm::mat4 rm = glm::toMat4(rot);
                           glm::mat4 sm = glm::scale(glm::mat4(1.f), sc);

                           newNode->localTransform = tm * rm * sm;
                       } },
            node.transform);
    }


    return .{

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
