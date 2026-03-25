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

    pub const Callback = *const fn (*anyopaque, path: []const u8, io: std.Io, allocator: std.mem.Allocator, file: std.Io.File) anyerror!void;

    pub fn init(allocator: std.mem.Allocator, io: std.Io, user_data: *anyopaque, path: []const u8, callback: Callback) !@This() {
        return .{
            .user_data = user_data,
            .mtime = .now(io, .real),
            .path = try allocator.dupe(u8, path),
            .callback = callback,
        };
    }
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) !void {
        allocator.free(self.path);
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
        .mtime = .now(io, .real),
    };
}

pub fn deinit(self: *@This()) void {
    self.dir.close(self.io);
    for (self.metadata.items) |*meta| {
        try meta.deinit(self.allocator);
    }
    self.metadata.deinit(self.allocator);
    self.* = undefined;
}

pub fn update(self: *@This()) !void {
    for (self.metadata.items) |*metadata| {
        const entry_stat = self.dir.statFile(self.io, metadata.path, .{}) catch |err| {
            if (err == error.FileNotFound) continue;
            std.debug.print("error: {any}\nfile: {s}\n", .{ err, metadata.path });
            continue;
        };

        if (entry_stat.mtime.nanoseconds > metadata.mtime.nanoseconds + std.time.ns_per_s) {
            std.debug.print("reload shader {s}\n", .{metadata.path});
            const file = try self.dir.openFile(self.io, metadata.path, .{});

            defer file.close(self.io);
            try metadata.callback(metadata.user_data, metadata.path, self.io, self.allocator, file);
            metadata.mtime = entry_stat.mtime;
        }
    }
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
        try self.metadata.append(
            self.allocator,
            try .init(self.allocator, self.io, user_data, path, callback),
        );
    }

    std.log.debug("path: {s}", .{path});
    const file = try self.dir.openFile(self.io, path, .{});
    defer file.close(self.io);
    try callback(user_data, path, self.io, self.allocator, file);
}
