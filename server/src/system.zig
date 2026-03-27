const std = @import("std");
const testing = @import("test.zig");
const shared = @import("shared");
const net = @import("system/net.zig");
const nz = shared.nz;
pub const ec = shared.ec;
// const Physics = @import("Physics.zig");
// physics: *Physics,

pub const Info = struct {
    delta_time: f32,
    elapsed_time: f32,
    world: *World,
};

pub const World = struct {
    mutex: std.Io.Mutex,
    ec: ec.World(&.{
        nz.Transform3D(f32),
    }),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .mutex = .init,
            .ec = try .init(allocator, null),
        };
    }
    pub fn deinit(self: *@This()) void {
        self.ec.deinit();
    }
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    accept_client_future: std.Io.Future(@typeInfo(@TypeOf(net.acceptClient)).@"fn".return_type.?),
    world: *World,
    io: std.Io,
    socket: std.Io.net.Socket,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        world: *World,
        io: std.Io,
    };

    pub fn init(self: *@This(), data: *const Data) !void {
        const address = try std.Io.net.IpAddress.parse(shared.net.server_ip, shared.net.server_port);
        self.* = .{
            .allocator = data.allocator,
            .io = data.io,
            .socket = try address.bind(data.io, .{ .protocol = .udp, .mode = .dgram }),
            .world = data.world,
            .accept_client_future = undefined,
        };
        self.accept_client_future = try data.io.concurrent(net.acceptClient, .{ data.io, &self.socket, data.world });
    }

    pub fn deinit(self: *@This()) !void {
        try self.accept_client_future.cancel(self.io);
        self.socket.close(self.io);
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        const world = info.world;
        _ = world;
        // std.debug.print("enetiess : {d}\n", .{world.ec.generation.items.len});
        _ = self;
    }
    fn reload(self: *@This(), pre_reload: bool) !void {
        if (pre_reload) try self.accept_client_future.cancel(self.io) else {
            self.accept_client_future = try self.io.concurrent(net.acceptClient, .{ self.io, &self.socket, self.world });
        }
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
