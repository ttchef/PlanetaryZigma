const std = @import("std");
const c = @import("vulkan");
const nz = @import("shared").nz;
const Device = @import("device.zig").Logical;
const Buffer = @import("Buffer.zig");
const Vma = @import("Vma.zig");

pub const box = @import("Meshes/box.zig");

pub const vertex_array = [_]Vertex{
    .{
        .position = .{ 0, 0, -1 },
        .color = .{ 1, 0, 0, 1 },
        .uv_x = 0,
        .uv_y = 0,
    },
    .{
        .position = .{ 1, 0, -1 },
        .color = .{ 0, 1, 0, 1 },
        .uv_x = 1,
        .uv_y = 0,
    },
    .{
        .position = .{ 0, -1, -1 },
        .color = .{ 0, 0, 1, 1 },
        .uv_y = 1,
        .uv_x = 0,
    },
    .{
        .position = .{ 1, -1, -1 },
        .color = .{ 0, 0, 1, 1 },
        .uv_y = 1,
        .uv_x = 1,
    },
    .{
        .position = .{ -0.75, 0.75, -1 },
        .color = .{ 1, 0, 0, 1 },
        .uv_x = 0,
        .uv_y = 0,
    },
    .{
        .position = .{ 0, 0.75, -1 },
        .color = .{ 0, 1, 0, 1 },
        .uv_x = 1,
        .uv_y = 0,
    },
    .{
        .position = .{ -0.75, -0.75, -1 },
        .color = .{ 0, 0, 1, 1 },
        .uv_y = 1,
        .uv_x = 0,
    },
};
pub const indicies_array = [_]u32{ 0, 1, 2, 1, 3, 2, 4, 5, 6 };

// surfaces: std.ArrayList(GeoSurface),
index_buffer: Buffer,
vertex_buffer: Buffer,
name: []const u8,

pub const Vertex = extern struct {
    position: [3]f32 = @splat(0),
    uv_x: f32 = 0,
    normal: [3]f32 = @splat(0),
    uv_y: f32 = 0,
    color: [4]f32 = @splat(0),
};

// pub const Bounds = struct {
//     origin: nz.Vec3(f32),
//     sphere_radius: f32,
//     extents: nz.Vec3(f32),
// };
//
// pub const GeoSurface = struct {
//     index_start: i32,
//     index_count: i32,
//     bounds: Bounds,
//     material: *const Material.Instance,
// };
//
pub fn init(
    allocator: std.mem.Allocator,
    vma: Vma,
    name: []const u8,
    device: Device,
    // geo_surfaces: []const GeoSurface,
    indices: []const u32,
    vertex_type: type,
    vertices: []const vertex_type,
) !@This() {
    var vertex_buffer: Buffer = try .init(
        device,
        vma,
        vertex_type,
        vertices.len,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT_KHR,
        .{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT | c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        },
    );
    vertex_buffer.copy(vertex_type, vertices);

    var index_buffer: Buffer = try .init(
        device,
        vma,
        u32,
        indices.len,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT_KHR,
        .{
            .usage = c.VMA_MEMORY_USAGE_AUTO,
            .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT | c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        },
    );
    index_buffer.copy(u32, indices);

    // var allocated_surfaces: std.ArrayList(GeoSurface) = try .initCapacity(allocator, geo_surfaces.len);
    // allocated_surfaces.appendSliceAssumeCapacity(geo_surfaces);

    return .{
        .index_buffer = index_buffer,
        .vertex_buffer = vertex_buffer,
        // .surfaces = allocated_surfaces,
        .name = try allocator.dupe(u8, name),
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator, vma: Vma) void {
    self.index_buffer.deinit(vma);
    self.vertex_buffer.deinit(vma);
    allocator.free(self.name);
    // self.surfaces.deinit(allocator);
}
