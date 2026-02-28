const std = @import("std");

allocator: std.mem.Allocator,
assets_root: []u8,

pub fn init(allocator: std.mem.Allocator, io: std.Io) !@This() {
    const root = try discoverAssetsRoot(allocator, io);
    return .{
        .allocator = allocator,
        .assets_root = root,
    };
}

pub fn deinit(self: *@This()) void {
    self.allocator.free(self.assets_root);
}

pub fn loadAsset(self: *@This(), io: std.Io, relative_path: []const u8) ![]u8 {
    const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.assets_root, relative_path });
    defer self.allocator.free(full_path);

    return try cwdDir().readFileAlloc(io, full_path, self.allocator, .unlimited);
}

pub fn loadAssetNullTerminated(self: *@This(), io: std.Io, relative_path: []const u8) ![:0]u8 {
    const bytes = try self.loadAsset(io, relative_path);
    defer self.allocator.free(bytes);
    return try self.allocator.dupeZ(u8, bytes);
}

fn discoverAssetsRoot(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    const candidates: []const []const u8 = &.{
        "assets",
        "../assets",
        "../../assets",
    };

    for (candidates) |candidate| {
        cwdDir().access(io, candidate, .{}) catch continue;
        return try allocator.dupe(u8, candidate);
    }

    return error.AssetsFolderNotFound;
}

fn cwdDir() std.Io.Dir {
    if (@hasDecl(std.Io, "cwd")) return std.Io.cwd();
    return std.Io.Dir.cwd();
}
