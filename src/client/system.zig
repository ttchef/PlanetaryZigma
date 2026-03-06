const std = @import("std");
const shared = @import("shared");
const yes = @import("yes");

const AssetServer = @import("shared").AssetServer;

pub const Renderer = @import("Renderer.zig");

pub const Context = struct {
    renderer: Renderer,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        asset_server: *AssetServer,
        platform: yes.Platform,
        window: *yes.Platform.Window,
    };

    pub fn init(data: Data) !@This() {
        return .{
            .renderer = try .init(data.allocator, data.asset_server, data.platform, data.window),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.renderer.deinit();
    }

    pub fn update(self: *@This(), detla_time: f32) !void {
        _ = detla_time;
        try self.renderer.update();
    }
};

comptime {
    _ = ffi;
}

pub const ffi = struct {
    pub const Table = struct {
        systemContextInit: *const fn (*Context, data: *const Context.Data) callconv(.c) void,
        systemContextDeinit: *const fn (*Context) callconv(.c) void,
        systemContextUpdate: *const fn (*Context, detla_time: f32) callconv(.c) void,

        pub fn load(dynlib: *std.DynLib) !@This() {
            var self: @This() = undefined;
            inline for (@typeInfo(@This()).@"struct".fields) |field| @field(self, field.name) = dynlib.lookup(field.type, field.name) orelse return error.DynlibLookup;
            return self;
        }
    };

    pub export fn systemContextInit(context: *Context, data: *const Context.Data) void {
        std.log.debug("system context init", .{});
        context.* = Context.init(data.*) catch |err| {
            std.log.err("context init: {any}", .{@errorName(err)});
            return;
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        std.log.debug("system context deinit", .{});
        context.deinit();
        context.* = undefined;
    }

    pub export fn systemContextUpdate(context: *Context, detla_time: f32) void {
        std.log.debug("system context update", .{});
        context.update(detla_time) catch |err| {
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
};
