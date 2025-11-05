const std = @import("std");
const tiny_obj = @import("tiny_obj_loader");

// Simple file reader callback for tiny_obj_loader
pub fn tinyObjFileReader(ctx: ?*anyopaque, filename: [*c]const u8, is_mtl: c_int, search_path: [*c]const u8, buffer: [*c][*c]u8, lengths: [*c]usize) callconv(.c) void {
    _ = ctx;
    _ = is_mtl;
    _ = search_path;

    const file = std.fs.cwd().openFile(std.mem.sliceTo(filename, 0), .{}) catch return;
    defer file.close();

    const stat = file.stat() catch return;
    const content = std.heap.c_allocator.alloc(u8, stat.size) catch return;
    _ = file.readAll(content) catch return;

    buffer.* = content.ptr;
    lengths.* = content.len;
}
