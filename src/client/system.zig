const std = @import("std");
const shared = @import("shared");

const glfw = @import("glfw");
const AssetServer = @import("shared").AssetServer;

pub const Renderer = @import("Renderer.zig");

pub const Context = struct {
    renderer: Renderer,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        asset_server: *AssetServer,
        window: *glfw.GLFWwindow,
    };

    pub fn init(data: Data) !@This() {
        return .{
            .renderer = try .init(data.allocator, data.asset_server, data.window),
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

// comptime {
//     _ = ffi;
// }

pub const ffi = struct {
    pub const Table = struct {
        systemContextInit: *const fn (*Context, data: *const Context.Data) void,
        systemContextDeinit: *const fn (*Context) void,
        systemContextUpdate: *const fn (*Context, detla_time: f32) void,
    };

    pub export fn systemContextInit(context: *Context, data: *const Context.Data) void {
        context.* = Context.init(data.*) catch |err| {
            std.log.err("context init: {}", .{@errorName(err)});
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        context.deinit();
        context.* = undefined;
    }

    pub export fn systemContextUpdate(context: *Context, detla_time: f32) void {
        context.update(detla_time) catch |err| {
            std.log.err("context update: {}", .{@errorName(err)});
        };
    }
};
