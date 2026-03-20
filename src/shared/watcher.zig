const std = @import("std");
const builtin = @import("builtin");

// lib_path_buffer: [std.fs.max_path_bytes]u8,
// lib_path_len: usize,

dynlib: ?std.DynLib = null,
dir_path: []const u8,
mtime: std.Io.Timestamp,
lib_name: []const u8,

pub fn init(comptime library_name: []const u8, io: std.Io) !@This() {
    // const lib_name = "lib" ++ library_name ++ comptime builtin.target.dynamicLibSuffix();
    const lib_name = "lib" ++ library_name;
    const search_paths: []const [:0]const u8 = &.{
        "../lib/",
        "zig-out/lib/",
        "./",
    };
    const found_path: []const u8 = path: for (search_paths) |path| {
        std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        break :path path;
    } else return error.NoAssetDir;

    return .{
        .dir_path = found_path,
        .mtime = .zero,
        .lib_name = lib_name,
    };

    // const lib_path: ?[]const u8 =
    //     for (search_paths) |path_prefix| {
    //         var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    //         const path = try std.fmt.bufPrint(&buffer, "{s}{s}", .{ path_prefix, lib_name });
    //
    //         if ((std.Io.Dir.cwd().access(io, path, .{}) catch null) != null) {
    //             break @constCast(path);
    //         }
    //     } else null;

    //if (lib_path == null or (std.fs.cwd().access(lib_path.?, .{}) catch null) != null) {
    //    std.log.warn("{s} not found", .{lib_path orelse "null"});
    //    std.process.cleanExit();
    //}

    // var file_watcher: FileWatcher = try .init();
    // try file_watcher.addFile("zig-out/lib/");
    //         const asset_paths: []const []const u8 = &.{
    //             "assets",
    //             "../assets",
    //             "../../assets",
    //         };
    //
    //         const found_path: []const u8 = path: for (asset_paths) |path| {
    //             std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
    //                 error.FileNotFound => continue,
    //                 else => return err,
    //             };
    //             break :path path;
    //         } else return error.NoAssetDir;
    //
    //         const dir = try std.Io.Dir.cwd().openDir(io, found_path, .{ .iterate = true });
    //
    //         return .{
    //             .dir = dir,
    //             .allocator = allocator,
    //             .io = io,
    //             .mtime = .now(io, .real),
    //         };

    // const dynlib: std.DynLib = try .open(lib_path.?);
    // std.log.debug("PATH {s}", .{lib_path.?});

    // var self: @This() = .{
    //     .lib_path_len = lib_path.?.len,
    //     .lib_path_buffer = undefined,
    //     .dynlib = dynlib,
    //     .file_watcher = file_watcher,
    // };
    // @memcpy(self.lib_path_buffer[0..lib_path.?.len], lib_path.?[0..]);
    // return self;
}

pub fn deinit(self: *@This(), io: std.Io) void {
    _ = io;
    if (self.dynlib) |*dynlib| dynlib.close();
}

pub fn load(self: *@This(), io: std.Io) !void {
    const dir = try std.Io.Dir.cwd().openDir(io, self.dir_path, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    std.log.debug("LIBNAME: {s}", .{self.lib_name});
    const file_name = while (try it.next(io)) |entry| {
        std.log.debug("FILE_NAME: {s}", .{entry.name});
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, self.lib_name)) continue;
        break entry.name;
    } else return error.FileNotFound;
    var full_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&full_path_buffer, "{s}{s}", .{ self.dir_path, file_name });
    std.log.debug("Full path: {s}", .{full_path});
    self.dynlib = std.DynLib.open(full_path) catch |err| {
        std.log.debug("Retry {}/{}: failed to open library: {}", .{ 1, 2, err });
        return err;
    };

    _ = self.dynlib.?.lookup(*const fn () void, "systemContextInit") orelse {
        std.log.debug("Retry {}/{}: library opened but symbols not available yet", .{ 1, 2 });
        self.dynlib.?.close();
        return error.TestSymbolLookup;
    };
    self.mtime = .now(io, .real);
}

pub fn reload(self: *@This(), io: std.Io) !bool {
    std.log.debug("PATH: {s}", .{self.dir_path});
    const dir = std.Io.Dir.cwd().openDir(io, self.dir_path, .{ .iterate = true }) catch return false;
    std.log.debug("PATH: {s}", .{self.dir_path});
    defer dir.close(io);
    const dir_stat = try dir.stat(io);
    if (dir_stat.mtime.nanoseconds <= self.mtime.nanoseconds) return false;

    const old_dynlib = self.dynlib;
    _ = old_dynlib;
    self.load(io) catch {
        // self.dynlib = old_dynlib;
        return false;
    };
    self.mtime = dir_stat.mtime;
    // if (old_dynlib) |*dynlib| dynlib.close();

    std.log.debug("Reloaded dynamic lib:\n, PATH {s}\n", .{self.lib_name});
    return true;
    //     return;
    // }
    // return error.DynlibOpenFailed;
}

pub inline fn lookup(self: *@This(), comptime T: type, name: [:0]const u8) !T {
    const function_pointer = self.dynlib.?.lookup(T, name);
    if (function_pointer == null) return error.DynlibLookup;
    return function_pointer.?;
}

// file_watcher: FileWatcher,

// const FileWatcher = struct {
//     inotify_fd: i32,
//
//     pub fn init() !@This() {
//         const asset_paths: []const []const u8 = &.{
//             "assets",
//             "../assets",
//             "../../assets",
//         };
//
//         const found_path: []const u8 = path: for (asset_paths) |path| {
//             std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
//                 error.FileNotFound => continue,
//                 else => return err,
//             };
//             break :path path;
//         } else return error.NoAssetDir;
//
//         const dir = try std.Io.Dir.cwd().openDir(io, found_path, .{ .iterate = true });
//
//         return .{
//             .dir = dir,
//             .allocator = allocator,
//             .io = io,
//             .mtime = .now(io, .real),
//         };
//     }
//
//     pub fn deinit(self: @This(), io: std.Io) void {
//         std.Io.Dir.close(.{ .handle = self.inotify_fd }, io);
//     }
//
//     pub fn addFile(self: *@This(), path: [:0]const u8) !void {
//         _ = try inotify_add_watchZ(self.inotify_fd, path, std.os.linux.IN.MODIFY);
//     }
//
//     pub fn listen(self: *@This()) !bool {
//         const max_event_size = @sizeOf(std.os.linux.inotify_event) + std.os.linux.NAME_MAX + 1;
//         var buffer: [max_event_size]u8 align(@alignOf(std.os.linux.inotify_event)) = undefined;
//
//         const read = std.posix.read(self.inotify_fd, &buffer) catch return false;
//         std.debug.print("listen: {any}\n", .{buffer[0..read]});
//         if (read > 0) return true;
//         return false;
//     }
// };
