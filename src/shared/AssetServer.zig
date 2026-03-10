const std = @import("std");

dir: std.Io.Dir,
allocator: std.mem.Allocator,
io: std.Io,
listeners: std.ArrayList(Listener) = .empty,

pub const Listener = struct {
    user_data: *anyopaque,
    dir: std.Io.Dir,
    callback: Callback,
    assets: std.AutoArrayHashMapUnmanaged(u16, Asset) = .empty,

    pub const Callback = *const fn (*anyopaque, io: std.Io, allocator: std.mem.Allocator, file: std.Io.File) anyerror!void;

    pub const Asset = struct {
        mtime: std.Io.Timestamp,

        pub const Key = enum(u16) {
            _,

            pub fn fromSlice(s: []const u8) @This() {
                var hash: u16 = 0;
                for (s) |c| hash = @intCast(hash *% 31 +% c);
                return hash;
            }
        };
    };

    pub fn listen(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
        var it = self.dir.iterate();
        while (try it.next()) |entry| if (entry.kind == .file) {
            const entry_stat = try self.dir.statFile(io, entry.name, .{});

            if (self.assets.getPtr(entry.name)) |asset| {
                if (entry_stat.mtime >= asset.mtime) continue;
                asset.mtime = entry_stat.mtime;

                const file = try self.dir.openFile(io, entry.name, .{});
                defer file.close(io);
                try self.callback(self.user_data, io, allocator, file);
            } else { // Doesnt exist
                try self.assets.put(allocator, .fromSlice(entry.name), .{ .mtime = entry_stat.mtime });
            }
        };
    }
};

pub fn init(allocator: std.mem.Allocator, io: std.Io) !@This() {
    const asset_paths: []const []const u8 = &.{
        "assets",
        "../assets",
        "../../assets",
    };

    const found_path: []const u8 = path: for (asset_paths) |path| {
        std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        break :path path;
    } else return error.NoAssetDir;

    const dir = try std.Io.Dir.cwd().openDir(io, found_path, .{ .iterate = true });

    return .{
        .dir = dir,
        .allocator = allocator,
        .io = io,
    };
}

pub fn deinit(self: *@This()) void {
    // for (self.listeners.items) |listener| listener.dir.close(self.io);
    self.dir.close(self.io);
    self.* = undefined;
}

pub fn addListener(self: *@This(), comptime UserData: type, user_data: *UserData, sub_path: []const u8, callback: Listener.Callback) !void {
    const listener: Listener = .{
        .user_data = @ptrCast(@alignCast(user_data)),
        .dir = try self.dir.openDir(self.io, sub_path, .{ .iterate = true, .access_sub_paths = true }),
        .callback = callback,
    };
    try self.listeners.append(self.allocator, listener);
}

pub fn listen(self: *@This()) !void {
    for (self.listeners.items) |*listener| try listener.listen(self.io, self.allocator);
}

/// Deprecated: use the asset server as intended
pub fn loadAsset(self: *@This(), sub_path: []const u8) ![]u8 {
    return self.dir.readFileAlloc(self.io, sub_path, self.allocator, .unlimited);
}

// fn loadTextureRgba8(
//     self: *@This(),
//     allocator: std.mem.Allocator,
//     io: std.Io,
//     relative_path: []const u8,
// ) !TextureImage {
//     const file_bytes = try self.loadAsset(io, relative_path);
//     defer allocator.free(file_bytes);
//
//     const NSData = objc.getClass("NSData") orelse return error.NoNSData;
//     const image_data = NSData.msgSend(objc.Object, "dataWithBytes:length:", .{
//         file_bytes.ptr,
//         @as(NSUInteger, @intCast(file_bytes.len)),
//     });
//     if (image_data.value == null) return error.NSDataCreateFailed;
//
//     const NSBitmapImageRep = objc.getClass("NSBitmapImageRep") orelse return error.NoNSBitmapImageRep;
//     const bitmap = NSBitmapImageRep.msgSend(objc.Object, "imageRepWithData:", .{image_data});
//     if (bitmap.value == null) return error.ImageDecodeFailed;
//
//     const width: usize = @intCast(bitmap.msgSend(NSUInteger, "pixelsWide", .{}));
//     const height: usize = @intCast(bitmap.msgSend(NSUInteger, "pixelsHigh", .{}));
//     if (width == 0 or height == 0) return error.InvalidImageDimensions;
//
//     const bits_per_pixel: usize = @intCast(bitmap.msgSend(NSUInteger, "bitsPerPixel", .{}));
//     const samples_per_pixel: usize = @intCast(bitmap.msgSend(NSUInteger, "samplesPerPixel", .{}));
//     const bytes_per_pixel = bits_per_pixel / 8;
//     if (bytes_per_pixel != 3 and bytes_per_pixel != 4) return error.UnsupportedPixelFormat;
//     if (samples_per_pixel < 3) return error.UnsupportedPixelFormat;
//
//     const src_bytes_per_row: usize = @intCast(bitmap.msgSend(NSUInteger, "bytesPerRow", .{}));
//     if (src_bytes_per_row < width * bytes_per_pixel) return error.UnsupportedPixelFormat;
//
//     const bitmap_data = bitmap.msgSend([*c]u8, "bitmapData", .{});
//     if (bitmap_data == null) return error.ImageDecodeFailed;
//
//     const bytes_per_row = width * 4;
//     const total_bytes = bytes_per_row * height;
//     const pixels = try allocator.alloc(u8, total_bytes);
//     errdefer allocator.free(pixels);
//     const src = @as([*]const u8, @ptrCast(bitmap_data));
//
//     var y: usize = 0;
//     while (y < height) : (y += 1) {
//         var x: usize = 0;
//         while (x < width) : (x += 1) {
//             const src_offset = y * src_bytes_per_row + x * bytes_per_pixel;
//             const dst_offset = y * bytes_per_row + x * 4;
//
//             pixels[dst_offset + 0] = src[src_offset + 0];
//             pixels[dst_offset + 1] = src[src_offset + 1];
//             pixels[dst_offset + 2] = src[src_offset + 2];
//             pixels[dst_offset + 3] = if (bytes_per_pixel == 4) src[src_offset + 3] else 255;
//         }
//     }
//
//     return .{
//         .pixels = pixels,
//         .width = @intCast(width),
//         .height = @intCast(height),
//         .bytes_per_row = bytes_per_row,
//     };
// }
