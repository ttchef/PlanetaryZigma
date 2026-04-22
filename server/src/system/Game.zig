const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const Spawner = @import("Spawner.zig");
const Info = system.Info;
const component = system.World.component;

gpa: std.mem.Allocator,
world: *system.World,
value: u32,

pub fn init(self: *@This(), gpa: std.mem.Allocator, world: *system.World) !void {
    self.* = .{
        .gpa = gpa,
        .value = 0,
        .world = world,
    };
}
pub fn deinit(self: *@This()) !void {
    _ = self;
}

pub fn update(self: *@This(), info: *const Info, spawner: *Spawner) !void {
    if (self.value < 20) {
        _ = try spawner.spawnEnemy();
        self.value += 1;
    }
    var player: *system.Entity = undefined;
    for (info.world.entities.values()) |*entity| {
        if (entity.kind == .player) {
            player = entity;
            if (player.input.mouse_button_left) {
                _ = try spawner.spawnEnemy();
            }
            break;
        }
    } else return;

    // for (info.world.entities.values()) |*entity| {
    //     if (entity.id == player.id) continue;
    //     if (!entity.flags.transform) continue;
    //     entity.transform.position = player.transform.position;
    // }
    // if (entity.flags.transform)

}
