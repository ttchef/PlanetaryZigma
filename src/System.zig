const zphy = @import("zphysics");
const std = @import("std");
const nz = @import("numz");
const player = @import("systems/player.zig");
const WorldModule = @import("World");
const World = WorldModule.World;

pub const Update = *const fn (*World, f32) callconv(.c) void;
// pub const InitSystems = *const fn (std.mem.Allocator) callconv(.c) u32;
// pub const DeinitSystems = *const fn (std.mem.Allocator) callconv(.c) u32;

pub fn init(allocator: std.mem.Allocator, world: *World) !void {
    const entity_player = try world.addEntity();
    entity_player.set(WorldModule.Player, .{}, world);
    entity_player.set(nz.Transform3D(f32), .{}, world);
    entity_player.set(WorldModule.Camera, .{}, world);

    const entity_gltf = try world.addEntity();
    entity_gltf.set(WorldModule.Model, .{ .model = .{ .gltf = 0 } }, world);
    const entity_mesh = try world.addEntity();
    entity_mesh.set(WorldModule.Model, .{ .model = .{ .mesh = 0 } }, world);

    try zphy.init(allocator, .{});
}
pub fn deinit() void {
    zphy.deinit();
}

export fn update(world: *World, delta_time: f32) void {
    player.update(@ptrCast(world), delta_time) catch @panic("\n\nMake a better panic xd,\n\n");
}
