const std = @import("std");
const vk = @import("../vulkan/vulkan.zig");

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

// fn load(file_path: []const u8) !@This() {
//     std.debug.print("Loading GLTF: {s}\n", .{filePath});
//
//     fastgltf::Parser parser {};
//
//     constexpr auto gltfOptions = fastgltf::Options::DontRequireValidAssetMember | fastgltf::Options::AllowDouble | fastgltf::Options::LoadGLBBuffers | fastgltf::Options::LoadExternalBuffers;
//     // fastgltf::Options::LoadExternalImages;
//
//     fastgltf::GltfDataBuffer data;
//     data.loadFromFile(filePath);
//
//     fastgltf::Asset gltf;
//
//     std::filesystem::path path = filePath;
//
//     auto type = fastgltf::determineGltfFileType(&data);
//     if (type == fastgltf::GltfType::glTF) {
//         auto load = parser.loadGLTF(&data, path.parent_path(), gltfOptions);
//         if (load) {
//             gltf = std::move(load.get());
//         } else {
//             std::cerr << "Failed to load glTF: " << fastgltf::to_underlying(load.error()) << std::endl;
//             return {};
//         }
//     } else if (type == fastgltf::GltfType::GLB) {
//         auto load = parser.loadBinaryGLTF(&data, path.parent_path(), gltfOptions);
//         if (load) {
//             gltf = std::move(load.get());
//         } else {
//             std::cerr << "Failed to load glTF: " << fastgltf::to_underlying(load.error()) << std::endl;
//             return {};
//         }
//     } else {
//         std::cerr << "Failed to determine glTF container" << std::endl;
//         return {};
//     }
// }
