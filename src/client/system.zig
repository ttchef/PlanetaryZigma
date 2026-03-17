const std = @import("std");
const shared = @import("shared");
const yes = @import("yes");
const Info = shared.Info;

const AssetServer = @import("shared").AssetServer;

pub const Renderer = @import("Renderer.zig");

pub const Context = struct {
    asset_server: *AssetServer,
    renderer: Renderer,
    allocator: std.mem.Allocator,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        asset_server: *AssetServer,
        platform: yes.Platform,
        window: *yes.Platform.Window,
    };
    pub const Time = struct {};

    pub fn init(data: Data) !@This() {
        return .{
            .asset_server = data.asset_server,
            .renderer = try .init(data.allocator, data.asset_server, data.platform, data.window),
            .allocator = data.allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.renderer.deinit(self.allocator);
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        try self.renderer.update(.{ .delta_time = info.delta_time, .elapsed_time = info.elapsed_time });
        try self.asset_server.update();
    }
};

comptime {
    _ = ffi;
}

pub const ffi = struct {
    pub const Table = struct {
        systemContextInit: *const fn (*Context, data: *const Context.Data) callconv(.c) void,
        systemContextDeinit: *const fn (*Context) callconv(.c) void,
        systemContextUpdate: *const fn (*Context, data: *const Info) callconv(.c) void,

        pub fn load(dynlib: *std.DynLib) !@This() {
            var self: @This() = undefined;
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                std.log.debug("Looking up symbol: {s}", .{field.name});
                const ptr = dynlib.lookup(field.type, field.name);
                if (ptr) |p| {
                    @field(self, field.name) = p;
                } else {
                    std.log.err("Failed to lookup symbol: {s}", .{field.name});
                    return error.DynlibLookup;
                }
            }
            return self;
        }
    };

    pub export fn systemContextInit(context: *Context, data: *const Context.Data) void {
        std.log.debug("system context init", .{});
        context.* = Context.init(data.*) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        std.log.debug("system context deinit", .{});
        context.deinit();
        context.* = undefined;
    }

    pub export fn systemContextUpdate(context: *Context, data: *const Info) void {
        // std.log.debug("system context update", .{});
        context.update(data) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
};
