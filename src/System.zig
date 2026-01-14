pub const Player = @import("systems/Player.zig");
const World = @import("root").World;

pub export fn update(world: *World, delta_time: f32) void {
    Player.update(@ptrCast(world), delta_time) catch @panic("LOL XD");
}
