const std = @import("std");
const Renderer = @import("Renderer.zig");
const sdl = @import("sdl");

pub const SUCCESS: u16 = 0;

pub fn toErr(err: u16) !void {
    if (err != SUCCESS) return @errorFromInt(err);
}

pub const Init = *const fn (*Renderer, *const std.mem.Allocator, *const Renderer.Config) callconv(.c) u16;
pub const Draw = *const fn (*Renderer, f32) callconv(.c) u16;
pub const FreqUpdate = *const fn (*Renderer, *sdl.SDL_Window) callconv(.c) u16;

pub export fn init(renderer: *Renderer, allocator: *const std.mem.Allocator, config: *const Renderer.Config) u16 {
    renderer.* = Renderer.init(allocator.*, config.*) catch |err| return @intFromError(err);
    return SUCCESS;
}

pub export fn draw(renderer: *Renderer, time: f32) u16 {
    renderer.draw(time) catch |err| return @intFromError(err);
    return SUCCESS;
}

pub export fn freqUpdate(renderer: *Renderer, window: *sdl.SDL_Window) u16 {
    renderer.camera.proccessCamera(window);
    return SUCCESS;
}
