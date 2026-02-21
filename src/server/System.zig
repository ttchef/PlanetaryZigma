const std = @import("std");
const Physics = @import("Physics.zig");

physics: *Physics,

// pub const UpdateSystems = *const fn (*@This()) callconv(.c) void;
pub const InitSystems = *const fn (*@This(), *std.mem.Allocator) callconv(.c) u32;
pub const DeinitSystems = *const fn (*@This(), *std.mem.Allocator) callconv(.c) void;
// pub const ReloadSystems = *const fn (*@This(), *std.mem.Allocator, bool) callconv(.c) void;

export fn initSystems(self: *@This(), allocator: *std.mem.Allocator) u32 {
    self.physics = Physics.init(allocator) catch |err| return @intFromError(err);
    return 0;
}
export fn deinit(self: *@This(), allocator: *std.mem.Allocator) void {
    // var query = world.query(&.{ecs.Collider});
    // while (query.next()) |entry| {
    //     var collider = entry.getPtr(ecs.Collider, world).?;
    //     if (collider.shape == .mesh) {
    //         collider.shape.mesh.vertices.deinit(allocator.*);
    //         collider.shape.mesh.indices.deinit(allocator.*);
    //     }
    // }
    //
    self.physics.deinit(allocator.*);
    allocator.destroy(self.physics);

    // for (0..self.mesh_shapes.items.len) |i| {
    //     self.mesh_shapes.items[i].indices.deinit(allocator.*);
    //     self.mesh_shapes.items[i].vertices.deinit(allocator.*);
    // }
    // self.mesh_shapes.deinit(allocator.*);
}
