const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const Spawner = @import("Spawner.zig");
const Info = system.Info;
const component = system.World.component;

gpa: std.mem.Allocator,
value: u32,

pub fn init(self: *@This(), gpa: std.mem.Allocator) !void {
    self.gpa = gpa;
    self.value = 0;
}
pub fn deinit(self: *@This()) !void {
    _ = self;
}

pub fn update(self: *@This(), info: *const Info, spawner: *Spawner) !void {
    _ = info;
    if (self.value < 20) {
        _ = try spawner.spawnEnemy();
        self.value += 1;
    }
}
