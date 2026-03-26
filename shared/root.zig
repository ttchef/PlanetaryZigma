const std = @import("std");

pub const nz = @import("numz");
pub const ec = @import("ecs");
pub const Watcher = @import("watcher.zig");
pub const AssetServer = @import("AssetServer.zig");

pub const Net = struct {
    pub const server_ip: []const u8 = "127.0.0.1";
    pub const server_port: u16 = 8080;
    pub const data_size: u32 = 1024;
    pub const Command = struct {
        id: u32,
        data: [data_size]u8,
    };
};
