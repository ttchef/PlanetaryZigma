const std = @import("std");

dir: std.Io.Dir,
allocator: std.mem.Allocator,
io: std.Io,

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
    self.dir.close(self.io);
    self.* = undefined;
}

pub fn loadAsset(self: *@This(), sub_path: []const u8) std.Io.Dir.ReadFileAllocError![]u8 {
    return self.dir.readFileAllocOptions(self.io, sub_path, self.allocator, .unlimited, .of(u8), null);
}

pub fn loadAssetZ(self: *@This(), sub_path: []const u8) std.Io.Dir.ReadFileAllocError![:0]u8 {
    return self.dir.readFileAllocOptions(self.io, sub_path, self.allocator, .unlimited, .of(u8), 0);
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
