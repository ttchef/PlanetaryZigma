const std = @import("std");
const shared = @import("shared");
const nz = shared.nz;
const yes = @import("yes");
pub const ec = shared.ec;
pub const Camera = @import("system/Camera.zig");

const AssetServer = @import("shared").AssetServer;

pub const Renderer = @import("Renderer.zig");

pub const Info = struct {
    delta_time: f32,
    elapsed_time: f32,
    world: *World,
};

pub const World = struct {
    mutex: std.Io.Mutex,
    ec: ec.World(&.{
        nz.Transform3D(f32),
        Camera,
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
    asset_server: *AssetServer,
    renderer: Renderer,
    allocator: std.mem.Allocator,
    stream: std.Io.net.Stream,
    io: std.Io,
    server_address: std.Io.net.IpAddress,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        asset_server: *AssetServer,
        platform: yes.Platform,
        window: *yes.Window,
        stream: std.Io.net.Stream,
        io: std.Io,
        server_address: std.Io.net.IpAddress,
    };

    pub fn init(data: Data) !@This() {
        return .{
            .asset_server = data.asset_server,
            .renderer = try .init(data.allocator, data.asset_server, data.platform, data.window),
            .allocator = data.allocator,
            .stream = data.stream,
            .io = data.io,
            .server_address = data.server_address,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.renderer.deinit(self.allocator);
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        var query = info.world.ec.query(&.{Camera});
        const camera = query.next().?.getPtr(Camera, info.world.ec).?;
        try camera.update(info);
        try self.renderer.update(info);
        try self.asset_server.update();
        const name = "lucas";
        const connect: shared.net.cmd.Connect = .{ .name_len = name.len, .name = name };
        var buffer: [1024]u8 = undefined;
        const size = try shared.net.cmd.writeBuf(
            &buffer,
            .{ .opcode = .connect },
            connect,
        );
        std.log.debug("buffer: {any}", .{buffer[0..size]});
        // var command: shared.net.Command = .{ .id = 234, .data = undefined };
        // @memcpy(command.data[0..6], "LOL10\x00");
        try self.stream.socket.send(self.io, &self.server_address, buffer[0..size]);
    }

    pub fn eventUpdate(self: *@This(), info: *const Info, event: *const yes.Window.Event) !void {
        _ = self;
        var query = info.world.ec.query(&.{Camera});
        const camera = query.next().?.getPtr(Camera, info.world.ec).?;
        try camera.eventUpdate(info, event);
    }
};

comptime {
    _ = ffi;
}

pub const ffi = struct {
    pub const Table = struct {
        systemContextInit: *const fn (*Context, data: *const Context.Data) callconv(.c) void,
        systemContextDeinit: *const fn (*Context) callconv(.c) void,
        systemContextUpdate: *const fn (*Context, data: *const Info, event: ?*const yes.Window.Event) callconv(.c) void,

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

    pub export fn systemContextUpdate(context: *Context, info: *const Info, event: ?*const yes.Window.Event) void {
        const result = if (event != null) context.eventUpdate(info, event.?) else context.update(info);
        result catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
};
