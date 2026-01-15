const nz = @import("numz");
const player = @import("systems/player.zig");
// pub const Camera = @import("systems/Camera.zig");
const World = @import("World").World;

pub const Update = *const fn (*World, f32) callconv(.c) void;

export fn update(world: *World, delta_time: f32) void {
    player.update(@ptrCast(world), delta_time) catch @panic("\n\nMake a better panic xd,\n\n");
}
