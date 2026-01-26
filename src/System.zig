const zphy = @import("zphysics");
const std = @import("std");
const nz = @import("numz");
const player = @import("systems/player.zig");
const Planet = @import("systems/Planet.zig");
const WorldModule = @import("World");
const World = WorldModule.World;
const Renderer = @import("Renderer");

pub const Update = *const fn (*World, f32) callconv(.c) void;
// pub const InitSystems = *const fn (std.mem.Allocator) callconv(.c) u32;
// pub const DeinitSystems = *const fn (std.mem.Allocator) callconv(.c) u32;

pub fn init(allocator: std.mem.Allocator, world: *World, renderer: *Renderer) !void {
    const entity_player = try world.addEntity();
    entity_player.set(WorldModule.Player, .{}, world);
    entity_player.set(nz.Transform3D(f32), .{}, world);
    entity_player.set(WorldModule.Camera, .{}, world);
    var planet_mesh2 = try Planet.init(allocator, .{ 0, 0, -10 }, 10);
    defer planet_mesh2.deinit(allocator);
    const box2: usize = try renderer.createMesh("planet2", planet_mesh2.indices.items, planet_mesh2.vertices.items);
    const entity_mesh2 = try world.addEntity();
    entity_mesh2.set(WorldModule.Model, .{ .model = .{ .mesh = box2 } }, world);

    var planet_mesh = try Planet.init(allocator, .{ 0, 0, 0 }, 6);
    defer planet_mesh.deinit(allocator);
    const box: usize = try renderer.createMesh("planet", planet_mesh.indices.items, planet_mesh.vertices.items);
    const entity_mesh = try world.addEntity();
    entity_mesh.set(WorldModule.Model, .{ .model = .{ .mesh = box } }, world);

    const entity_gltf = try world.addEntity();
    const gltf_handle = try renderer.loadGltf("assets/objects/tree.glb");
    entity_gltf.set(WorldModule.Model, .{ .model = .{ .gltf = gltf_handle } }, world);

    const entity_gltf2 = try world.addEntity();
    const gltf_handle2 = try renderer.loadGltf("assets/objects/bag.glb");
    entity_gltf2.set(WorldModule.Model, .{ .model = .{ .gltf = gltf_handle2 } }, world);

    try zphy.init(allocator, .{});
}
pub fn deinit() void {
    zphy.deinit();
}

export fn update(world: *World, delta_time: f32) void {
    player.update(@ptrCast(world), delta_time) catch @panic("\n\nMake a better panix xd,\n\n");
}
