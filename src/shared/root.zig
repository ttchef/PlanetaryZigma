const std = @import("std");

pub const nz = @import("numz");
pub const ec = @import("ecs");
pub const Watcher = @import("watcher.zig");

pub const World = struct {
    mutex: std.Io.Mutex,
    ec: ec.World(&.{
        nz.Transform3D(f32),
    }),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .mutex = .init,
            .ec = try .init(allocator, null),
        };
    }
    pub fn deinit(self: *@This()) void {
        self.ec.deinit();
    }
};

pub const net = struct {
    pub const address: std.Io.net.IpAddress = .{ .ip4 = .{
        .bytes = .{ 127, 0, 0, 1 },
        .port = 8001,
    } };
};
