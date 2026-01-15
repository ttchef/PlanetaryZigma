const Renderer = @import("Renderer.zig");
const std = @import("std");
const sdl = @import("sdl");
const nz = @import("numz");

pub const SUCCESS: u16 = 0;

pub fn toErr(err: u16) !void {
    if (err != SUCCESS) return @errorFromInt(err);
}

pub const Init = *const fn (*Renderer, *const std.mem.Allocator, *const Renderer.Config) callconv(.c) u16;
pub const Draw = *const fn (*Renderer, *const Renderer.Camera, *const nz.Transform3D(f32), f32) callconv(.c) u16;

pub export fn init(renderer: *Renderer, allocator: *const std.mem.Allocator, config: *const Renderer.Config) u16 {
    renderer.* = Renderer.init(allocator.*, config.*) catch |err| return @intFromError(err);
    return SUCCESS;
}

pub export fn draw(renderer: *Renderer, camera: *const Renderer.Camera, camera_transform: *const nz.Transform3D(f32), time: f32) u16 {
    renderer.draw(camera, camera_transform, time) catch |err| return @intFromError(err);
    return SUCCESS;
}
