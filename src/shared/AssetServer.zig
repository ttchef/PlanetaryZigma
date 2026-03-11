const std = @import("std");

dir: std.Io.Dir,
allocator: std.mem.Allocator,
io: std.Io,
mtime: std.Io.Timestamp,
metadata: std.ArrayList(Metadata) = .empty,

pub const Metadata = struct {
    user_data: *anyopaque,
    path: []const u8,
    mtime: std.Io.Timestamp,
    callback: Callback,
    // assets: std.AutoArrayHashMapUnmanaged(u16, Asset) = .empty,

    pub const Callback = *const fn (*anyopaque, path: []const u8, io: std.Io, allocator: std.mem.Allocator, file: std.Io.File) anyerror!void;

    // pub const Asset = struct {
    //     mtime: std.Io.Timestamp,

    //     pub const Key = enum(u16) {
    //         _,

    //         pub fn fromSlice(s: []const u8) @This() {
    //             var hash: u16 = 0;
    //             for (s) |c| hash = @intCast(hash *% 31 +% c);
    //             return hash;
    //         }
    //     };
    // };

    // pub fn listen(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
    //     var it = self.dir.iterate();
    //     while (try it.next()) |entry| if (entry.kind == .file) {
    //         const entry_stat = try self.dir.statFile(io, entry.name, .{});

    //         if (self.assets.getPtr(entry.name)) |asset| {
    //             if (entry_stat.mtime >= asset.mtime) continue;
    //             asset.mtime = entry_stat.mtime;

    //             const file = try self.dir.openFile(io, entry.name, .{});
    //             defer file.close(io);
    //             try self.callback(self.user_data, io, allocator, file);
    //         } else { // Doesnt exist
    //             try self.assets.put(allocator, .fromSlice(entry.name), .{ .mtime = entry_stat.mtime });
    //         }
    //     };
    // }
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
        .mtime = .now(io, .real),
    };
}

pub fn deinit(self: *@This()) void {
    self.dir.close(self.io);
    self.* = undefined;
}

pub fn update(self: *@This()) !void {
    // var it = self.dir.iterate();
    // const stat = try self.dir.stat(self.io);
    // if (stat.mtime.nanoseconds > self.mtime.nanoseconds + std.time.ns_per_s) {
    // std.debug.print("info: {any}\n", .{stat.mtime});
    for (self.metadata.items) |*metadata| {
        const entry_stat = try self.dir.statFile(self.io, metadata.path, .{});
        if (entry_stat.mtime.nanoseconds > metadata.mtime.nanoseconds + std.time.ns_per_s) {
            std.debug.print("reload shader {s}\n", .{metadata.path});
            const file = try self.dir.openFile(self.io, metadata.path, .{});

            defer file.close(self.io);
            try metadata.callback(metadata.user_data, metadata.path, self.io, self.allocator, file);
            metadata.mtime = entry_stat.mtime;
        }
    }
    // self.mtime = stat.mtime;
    // }
    // while (try it.next(self.io)) |entry| {
    //     const entry_stat = try self.dir.statFile(self.io, entry.name, .{});
    //     _ = entry_stat;
    //
    //     std.debug.print("sub path: {s}\n", .{entry.name});
    // if (self.assets.getPtr(entry.name)) |asset| {
    //     if (entry_stat.mtime >= asset.mtime) continue;
    //     asset.mtime = entry_stat.mtime;
    //
    //     const file = try self.dir.openFile(io, entry.name, .{});
    //     defer file.close(io);
    //     try self.callback(self.user_data, io, allocator, file);
    // } else { // Doesnt exist
    //     try self.assets.put(allocator, .fromSlice(entry.name), .{ .mtime = entry_stat.mtime });
    // }
    // }
    //
    // };
}

pub fn loadAsset(self: *@This(), comptime UserData: type, user_data: *UserData, path: []const u8, callback: Metadata.Callback) !void {
    var metadata: ?usize = null;
    for (self.metadata.items, 0..) |meta, i| {
        if (std.mem.eql(u8, meta.path, path) == true) {
            metadata = i;
            break;
        }
    }
    if (metadata == null) {
        try self.metadata.append(self.allocator, .{
            .callback = callback,
            .path = path,
            .user_data = user_data,
            .mtime = .now(self.io, .real),
        });
    }

    const file = try self.dir.openFile(self.io, path, .{});
    defer file.close(self.io);
    try callback(user_data, path, self.io, self.allocator, file);
}
