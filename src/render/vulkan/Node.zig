const std = @import("std");
const vk = @import("vulkan");
const nz = @import("numz");
const Mesh = @import("Mesh.zig");
const Material = @import("Material.zig");

parent: ?*@This() = null,
mesh: ?*Mesh = null,
material: *Material.Instance = undefined,
children: std.ArrayList(*@This()) = .empty,
local_transform: nz.Transform3D(f32) = undefined,
world_transform: nz.Transform3D(f32) = undefined,

pub fn refreshTransform(self: *@This(), parent_transform: *nz.Transform3D(f32)) void {
    self.world_transform = nz.Transform3D(f32).fromMat4x4(parent_transform.toMat4x4().mul(self.local_transform.toMat4x4()));
    for (self.children.items[0..self.children.items.len]) |child| {
        child.refreshTransform(&self.world_transform);
    }
}

pub fn draw(self: *@This(), allocator: std.mem.Allocator, top_transform: nz.Transform3D(f32), ctx: *DrawContext) !void {
    const node_transform: nz.Transform3D(f32) = .fromMat4x4(top_transform.toMat4x4().mul(self.world_transform.toMat4x4()));
    for (self.mesh.?.surfaces.items[0..self.mesh.?.surfaces.items.len]) |surface| {
        try ctx.opaque_surfaces.append(allocator, .{
            .index_count = @intCast(surface.index_count),
            .first_index = @intCast(surface.index_start),
            .index_buffer = self.mesh.?.index_buffer.buffer,
            .material_instance = self.material.*,
            .transform = node_transform,
            .vertex_buffer_address = self.mesh.?.vertex_buffer_address,
        });
        ctx.count += 1;
    }

    for (self.children.items) |*child| {
        try child.*.draw(allocator, top_transform, ctx);
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
    opaque_surfaces: std.ArrayList(RenderObject) = .empty,
    count: usize = 0,

    pub fn clear(self: *@This()) void {
        self.count = 0;
        self.opaque_surfaces.clearRetainingCapacity();
    }
};
