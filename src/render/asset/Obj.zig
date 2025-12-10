const std = @import("std");
const tiny_obj = @import("tiny_obj_loader");

// Simple file reader callback for tiny_obj_loader
pub fn tinyObjFileReader(ctx: ?*anyopaque, filename: [*c]const u8, is_mtl: c_int, search_path: [*c]const u8, buffer: [*c][*c]u8, lengths: [*c]usize) callconv(.c) void {
    _ = ctx;
    _ = is_mtl;
    _ = search_path;

    std.debug.print("Path  {s}\n", .{filename});

    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    const io: std.Io = threaded.io();

    const file = std.Io.Dir.cwd().openFile(io, std.mem.span(filename), .{}) catch return;
    defer file.close(io);

    const file_len: usize = @intCast((file.stat(io) catch @panic("file size failed")).size);
    const alloc_content = std.heap.c_allocator.alloc(u8, file_len) catch @panic("tiny_obj_loader buffer failed allocation");
    var reader = file.reader(io, alloc_content);
    const content = reader.interface.take(file_len) catch @panic("failed to read");

    buffer.* = content.ptr;
    lengths.* = content.len;
}
