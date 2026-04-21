const std = @import("std");
const system = @import("../system.zig");
const shared = @import("shared");
const Info = system.Info;
const component = system.World.component;
const nz = shared.nz;

const SpawnEntity = struct {
    entity_type: shared.EntityType,
    id: u32,
};

gpa: std.mem.Allocator,
world: *system.World,
network_pending_spawn: std.ArrayList(SpawnEntity) = .empty,
network_pending_despawn: std.ArrayList(u32) = .empty,
// spawn_queue: std.ArrayList(SpawnEntity) = .empty,
// despawn_queue: std.ArrayList(u32) = .empty,

pub fn init(self: *@This(), gpa: std.mem.Allocator, world: *system.World) !void {
    self.* = .{
        .gpa = gpa,
        .world = world,
    };
}
pub fn deinit(self: *@This()) void {
    self.despawn_queue.deinit(self.gpa);
    self.spawn_queue.deinit(self.gpa);
}

pub fn spawnConnectPlayer(self: *@This()) !u32 {
    var entity = try self.world.ecz.spawnEntity();
    _ = try entity.putComponent(component.transform, .{ .position = .{ 0, 0, 100 } });
    _ = try entity.putComponent(component.collider, .{
        .shape = .{
            .primitive = .box,
        },
        .motion_type = .dynamic,
    });
    _ = try entity.putComponent(component.entity_type, .player);
    _ = try entity.addComponent(component.input);
    _ = try entity.putComponent(component.camera, .{ .transform = .{ .position = .{ 0, 0, 100 } } });

    try self.network_pending_spawn.append(self.gpa, .{ .id = entity.id, .entity_type = .player });
    return entity.id;
}

pub fn spawnEnemy(self: *@This()) !u32 {
    var entity = try self.world.ecz.spawnEntity();
    _ = try entity.putComponent(component.transform, .{ .position = .{ 0, 0, 100 } });
    _ = try entity.putComponent(component.collider, .{
        .shape = .{
            .primitive = .box,
        },
        .motion_type = .dynamic,
    });
    _ = try entity.putComponent(component.entity_type, .enemy);
    try self.network_pending_spawn.append(self.gpa, .{ .id = entity.id, .entity_type = .enemy });
    return entity.id;
}

pub fn depspawn(self: *@This(), entity_id: u32) !void {
    std.log.debug("despawn ID: {d}", .{entity_id});
    const entity = self.world.ecz.entityFromId(entity_id);
    try self.world.ecz.despawnEntity(entity);
    try self.network_pending_despawn.append(self.gpa, entity_id);
}

pub fn update(self: *@This()) !void {
    _ = self;
}
