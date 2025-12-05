const std = @import("std");
const Renderer = @import("Renderer.zig");

pub const SUCCESS: u16 = 0;

pub fn toErr(err: u16) !void {
    if (err != SUCCESS) return @errorFromInt(err);
}

pub const Init = *const fn (*Renderer, *const std.mem.Allocator, *const Renderer.Config) callconv(.c) u16;

pub export fn init(renderer: *Renderer, allocator: *const std.mem.Allocator, config: *const Renderer.Config) u16 {
    renderer.* = Renderer.init(allocator.*, config.*) catch |err| return @intFromError(err);
    return SUCCESS;
}



