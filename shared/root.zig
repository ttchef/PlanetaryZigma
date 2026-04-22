const std = @import("std");

pub const numz = @import("numz");
pub const ecz = @import("ecz");
pub const net = @import("net.zig");
pub const Planet = @import("Planet.zig");

pub const Watcher = @import("watcher.zig");
pub const AssetServer = @import("AssetServer.zig");

pub const EntityKind = enum(u16) {
    unknown,
    player,
    planet,
    enemy,
};
