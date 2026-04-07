const std = @import("std");
const testing = @import("test.zig");
const shared = @import("shared");
const NetworkManager = @import("system/NetworkManager.zig");
const nz = shared.numz;
pub const ecz = shared.ecz;
const Physics = @import("system/Physics.zig");

pub const Info = struct {
    delta_time: f32,
    elapsed_time: f32,
    world: *World,
};

pub const World = struct {
    mutex: std.Io.Mutex,

    ecz: ecz.World(&.{
        component.transform,
        component.collider,
        component.input,
    }),

    pub const component = struct {
        pub const transform: ecz.Component = .{ .name = .transform, .type = nz.Transform3D(f32) };
        pub const collider: ecz.Component = .{ .name = .collider, .type = Physics.Collider };
        pub const input: ecz.Component = .{ .name = .input, .type = shared.net.Command.Input };
    };

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .mutex = .init,
            .ecz = .init(allocator),
        };
    }
    pub fn deinit(self: *@This()) void {
        self.ecz.deinit();
    }
};

pub const Context = struct {
    request_exit: bool,
    allocator: std.mem.Allocator,
    world: *World,
    io: std.Io,
    network_manager: NetworkManager,
    physics: Physics,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        world: *World,
        io: std.Io,
    };

    pub fn init(self: *@This(), data: *const Data) !void {
        self.* = .{
            .request_exit = false,
            .allocator = data.allocator,
            .io = data.io,
            .world = data.world,
            .network_manager = undefined,
            .physics = undefined,
        };
        try self.network_manager.init(data.allocator, data.io);
        try self.physics.init(data.allocator, data.io);
    }

    pub fn deinit(self: *@This()) !void {
        try self.network_manager.deinit();
        self.physics.deinit();
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        try self.network_manager.update(info);
        try self.physics.update(info);
        // self.request_exit = true;
        // if (info.elapsed_time > 1) self.request_exit = true;
    }
    fn reload(self: *@This(), pre_reload: bool) !void {
        std.log.debug("before-1", .{});
        self.physics.reload(pre_reload, self.world);
        try self.network_manager.reload(pre_reload);
        std.log.debug("before-0", .{});
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
        systemContextReload: *const fn (*Context, pre_reload: bool) callconv(.c) void,

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
        context.init(data) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        std.log.debug("system context deinit", .{});
        context.deinit() catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
        context.* = undefined;
    }

    pub export fn systemContextUpdate(context: *Context, info: *const Info) void {
        const result = context.update(info);
        result catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
    pub export fn systemContextReload(context: *Context, pre_reload: bool) void {
        const result = context.reload(pre_reload);
        result catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
};
