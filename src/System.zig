const std = @import("std");
const nz = @import("numz");
const sdl = @import("sdl");
const player = @import("systems/player.zig");
const Planet = @import("systems/Planet.zig");
pub const Physics = @import("systems/physics.zig");
const WorldModule = @import("World");
const World = WorldModule.World;
const Renderer = @import("Renderer");

physics_system: *Physics = undefined,
renderer: Renderer = undefined,

pub const UpdateSystems = *const fn (*@This(), *World, f32) callconv(.c) void;
pub const InitSystems = *const fn (*@This(), *std.mem.Allocator, *World, *Renderer.Config) callconv(.c) u32;
pub const DeinitSystems = *const fn (*@This(), *std.mem.Allocator) callconv(.c) void;
pub const ReloadSystems = *const fn (*@This(), *std.mem.Allocator, *World, *Renderer.Config, bool) callconv(.c) void;
export fn reload(self: *@This(), allocator: *std.mem.Allocator, world: *World, render_config: *Renderer.Config, pre_reload: bool) u32 {
    if (pre_reload) {
        self.renderer.deinit(allocator.*);
        self.physics_system.deinit(allocator.*);
    } else {
        self.renderer = Renderer.init(allocator.*, render_config.*) catch |err| return @intFromError(err);
        self.physics_system = Physics.init(allocator, world) catch |err| return @intFromError(err);
    }
    return 0;
}

export fn initSystems(self: *@This(), allocator: *std.mem.Allocator, world: *World, renderer_config: *Renderer.Config) u32 {
    self.renderer = Renderer.init(allocator.*, renderer_config.*) catch |err| return @intFromError(err);
    initEcs(allocator.*, world, &self.renderer) catch |err| return @intFromError(err);
    self.physics_system = Physics.init(allocator, world) catch |err| return @intFromError(err);
    return 0;
}
export fn deinit(self: *@This(), allocator: *std.mem.Allocator) void {
    self.physics_system.deinit(allocator.*);
    allocator.destroy(self.physics_system);
    self.renderer.deinit(allocator.*);
}

export fn update(self: *@This(), world: *World, delta_time: f32) u32 {
    self.physics_system.update(world, delta_time);
    player.update(@ptrCast(world), @ptrCast(self.physics_system.physics_system), delta_time) catch @panic("\n\nMake a better panix xd,\n\n");
    self.renderer.draw(world, delta_time) catch |err| return @intFromError(err);
    return 0;
}

fn initEcs(allocator: std.mem.Allocator, world: *World, renderer: *Renderer) !void {
    // _ = renderer;
    // _ = allocator;
    const entity_player = try world.addEntity();
    entity_player.set(WorldModule.Player, .{}, world);
    entity_player.set(nz.Transform3D(f32), .{ .position = .{ 0, 0, 10 } }, world);
    entity_player.set(WorldModule.Camera, .{}, world);
    entity_player.set(WorldModule.Collider, .{ .shape = .{ .primitive = .capsule }, .max_angular_velocity = 0 }, world);

    var planet_mesh2 = try Planet.init(allocator, .{ 0, 0, 0 }, 10);
    defer planet_mesh2.deinit(allocator);
    const box2: usize = try renderer.createMesh("planet2", planet_mesh2.indices.items, planet_mesh2.vertices.items);
    const entity_mesh2 = try world.addEntity();
    entity_mesh2.set(WorldModule.Model, .{ .model = .{ .mesh = box2 } }, world);
    entity_mesh2.set(nz.Transform3D(f32), .{}, world);
    entity_mesh2.set(WorldModule.Collider, .{ .shape = .{ .primitive = .capsule } }, world);

    // var planet_mesh = try Planet.init(allocator, .{ 0, 0, 0 }, 6);
    // defer planet_mesh.deinit(allocator);
    // const box: usize = try renderer.createMesh("planet", planet_mesh.indices.items, planet_mesh.vertices.items);
    // const entity_mesh = try world.addEntity();
    // entity_mesh.set(WorldModule.Model, .{ .model = .{ .mesh = box } }, world);
    // entity_mesh.set(nz.Transform3D(f32), .{}, world);
    //
    const entity_gltf = try world.addEntity();
    const gltf_handle = try renderer.loadGltf("assets/objects/tree.glb");
    entity_gltf.set(WorldModule.Model, .{ .model = .{ .gltf = gltf_handle } }, world);
    entity_gltf.set(nz.Transform3D(f32), .{}, world);
    //
    // const entity_gltf2 = try world.addEntity();
    // const gltf_handle2 = try renderer.loadGltf("assets/objects/bag.glb");
    // entity_gltf2.set(WorldModule.Model, .{ .model = .{ .gltf = gltf_handle2 } }, world);
    // entity_gltf2.set(nz.Transform3D(f32), .{}, world);
}
