const std = @import("std");
const vk = @import("vulkan");
const nz = @import("numz");
const Mesh = @import("Mesh.zig");
const Material = @import("Material.zig");

parent: ?*@This() = null,
mesh: Mesh,
material: *Material.Instance,
children: std.ArrayList(@This()) = .empty,
local_transform: nz.Transform3D(f32),
world_transform: nz.Transform3D(f32),

pub fn refreshTransform(self: *@This(), parent_transform: *nz.Transform3D(f32)) void {
    self.world_transform = .fromMat4x4(parent_transform).mul(self.local_transform);
    for (0..self.child_count) |i| {
        self.children[i].refreshTransform(self.world_transform);
    }
}

pub fn draw(self: *@This(), top_transform: nz.Transform3D(f32), ctx: *DrawContext) void {
    const node_transform: nz.Transform3D(f32) = .fromMat4x4(top_transform.toMat4x4().mul(self.world_transform.toMat4x4()));
    ctx.opaque_surfaces[ctx.count] = .{
        .index_count = self.mesh.indecies_count,
        .first_index = self.mesh.first_index,
        .index_buffer = self.mesh.index_buffer.buffer,
        .material_instance = self.material.*,
        .transform = node_transform,
        .vertex_buffer_address = self.mesh.vertex_buffer_address,
    };
    ctx.count += 1;

    for (self.children.items) |*child| {
        child.*.draw(top_transform, ctx);
    }
}

const RenderObject = struct {
    index_count: u32,
    first_index: u32,
    index_buffer: vk.VkBuffer,
    vertex_buffer_address: vk.VkDeviceAddress,
    material_instance: Material.Instance,
    transform: nz.Transform3D(f32),
};

pub const DrawContext = struct {
    opaque_surfaces: [4]RenderObject = undefined,
    count: usize = 0,

    pub fn clear(self: *@This()) void {
        self.* = .{};
    }
};
