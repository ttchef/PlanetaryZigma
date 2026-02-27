const std = @import("std");
const testing = @import("test.zig");
// const Physics = @import("Physics.zig");

// physics: *Physics,

pub const InitSystems = *const fn (*@This(), *std.mem.Allocator) callconv(.c) u32;
pub const DeinitSystems = *const fn (*@This(), *std.mem.Allocator) callconv(.c) void;
pub const UpdateSystems = *const fn (*@This(), f32) callconv(.c) void;

export fn initSystems(self: *@This(), allocator: *std.mem.Allocator) u32 {
    _ = self;
    _ = allocator;
    return 0;
}

export fn deinit(self: *@This(), allocator: *std.mem.Allocator) void {
    _ = self;
    _ = allocator;
}

export fn update(self: *@This(), delta_time: f32) void {
    _ = delta_time;
    _ = self;
}
