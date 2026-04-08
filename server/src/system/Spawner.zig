const std = @import("std");
const system = @import("../system.zig");
const shared = @import("shared");
const nz = shared.nz;
const SpawnEntity = struct {
    entity_type: shared.EntityType,
};

allocator: std.mem.Allocator,
world: *system.World,
spawn_queue: std.ArrayList(SpawnEntity) = .empty,
despawn_queue: std.ArrayList(u32) = .empty,

pub fn init(self: *@This(), allocator: std.mem.Allocator, world: *system.World) !void {
    self.* = .{
        .allocator = allocator,
        .world = world,
    };
}
pub fn deinit(self: *@This()) void {
    self.despawn_queue.deinit(self.allocator);
    self.spawn_queue.deinit(self.allocator);
}

pub fn update(self: *@This()) !void {
    _ = self;
}
