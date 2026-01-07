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
    if (self.mesh) |mesh| {
        for (mesh.surfaces.items[0..mesh.surfaces.items.len]) |surface| {
            const render_obj: RenderObject = .{
                .index_count = @intCast(surface.index_count),
                .first_index = @intCast(surface.index_start),
                .index_buffer = mesh.index_buffer.buffer,
                .material_instance = surface.material,
                .transform = node_transform,
                .vertex_buffer_address = mesh.vertex_buffer_address,
            };
            if (surface.material.pass_type == .transparent) {
                try ctx.transparent_surfaces.append(allocator, render_obj);
            } else {
                try ctx.opaque_surfaces.append(allocator, render_obj);
            }
        }
    }

    for (self.children.items) |*child| {
        try child.*.draw(allocator, top_transform, ctx);
    }
}

pub const RenderObject = struct {
    index_count: u32,
    first_index: u32,
    index_buffer: vk.VkBuffer,
    vertex_buffer_address: vk.VkDeviceAddress,
    material_instance: *Material.Instance,
    transform: nz.Transform3D(f32),
};

pub const DrawContext = struct {
    opaque_surfaces: std.ArrayList(RenderObject) = .empty,
    transparent_surfaces: std.ArrayList(RenderObject) = .empty,

    pub fn clear(self: *@This()) void {
        self.opaque_surfaces.clearRetainingCapacity();
        self.transparent_surfaces.clearRetainingCapacity();
    }
};
