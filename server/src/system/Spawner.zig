const std = @import("std");
const system = @import("../system.zig");
const shared = @import("shared");
const Info = system.Info;
const nz = shared.nz;

const SpawnEntity = struct {
    entity_type: shared.EntityType,
    id: u32,
};

gpa: std.mem.Allocator,
world: *system.World,
network_pending_spawn: std.ArrayList(SpawnEntity) = .empty,
network_pending_despawn: std.ArrayList(u32) = .empty,

pub fn init(self: *@This(), gpa: std.mem.Allocator, world: *system.World) !void {
    self.* = .{
        .gpa = gpa,
        .world = world,
    };
}
pub fn deinit(self: *@This()) void {
    self.network_pending_despawn.deinit(self.gpa);
    self.network_pending_spawn.deinit(self.gpa);
}

pub fn spawnConnectPlayer(self: *@This()) !u32 {
    const entity = try self.world.spawn();
    entity.entity_type = .player;
    entity.transform = .{ .position = .{ 0, 0, 100 } };
    entity.collider = .{
        .shape = .{ .primitive = .box },
        .motion_type = .dynamic,
    };
    entity.camera = .{ .transform = .{ .position = .{ 0, 0, 100 } } };
    entity.flags = .{
        .transform = true,
        .collider = true,
        .input = true,
        .camera = true,
    };

    try self.network_pending_spawn.append(self.gpa, .{ .id = entity.id, .entity_type = .player });
    return entity.id;
}

pub fn spawnEnemy(self: *@This()) !u32 {
    const entity = try self.world.spawn();
    entity.entity_type = .enemy;
    entity.transform = .{ .position = .{ 0, 0, 100 } };
    entity.collider = .{
        .shape = .{ .primitive = .box },
        .motion_type = .dynamic,
    };
    entity.flags = .{ .transform = true, .collider = true };

    try self.network_pending_spawn.append(self.gpa, .{ .id = entity.id, .entity_type = .enemy });
    return entity.id;
}

pub fn spawnPlanet(self: *@This()) !u32 {
    const planet_entity = try self.world.spawn();
    const planet_size: u32 = 100;
    planet_entity.entity_type = .planet;
    planet_entity.planet = planet_size;
    planet_entity.transform = .{};
    const planet: shared.Planet = try .init(self.gpa, planet_size);
    std.log.debug("ptr: {*}, len:{d}", .{ planet.vertices.items.ptr, planet.vertices.items.len });

    planet_entity.collider = .{
        .shape = .{
            .mesh = .{
                .indices = planet.indices,
                .vertices = planet.vertices,
            },
        },
        .motion_type = .static,
    };
    planet_entity.flags = .{ .transform = true, .collider = true, .planet = true };
    std.log.debug("OK ", .{});
    return planet_entity.id;
}

pub fn depspawn(self: *@This(), entity_id: u32) !void {
    std.log.debug("despawn ID: {d}", .{entity_id});
    _ = self.world.despawn(entity_id);
    try self.network_pending_despawn.append(self.gpa, entity_id);
}

pub fn update(self: *@This()) !void {
    _ = self;
}
