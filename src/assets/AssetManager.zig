const std = @import("std");
const Obj = @import("Obj.zig");

meshes: std.AutoHashMapUnmanaged(u16, u64),

pub fn init() !void {}
