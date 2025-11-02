const std = @import("std");
const Mesh = @import("../vulkan/Mesh.zig");
const ObjLoader = @import("ObjLoader.zig");

meshs: std.StringHashMapUnmanaged(Mesh),
