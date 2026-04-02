const std = @import("std");
const shared = @import("shared");
const nz = shared.nz;
const yes = @import("yes");
pub const ec = shared.ec;
const NetworkManager = @import("system/NetworkManager.zig");
const AssetServer = @import("shared").AssetServer;
pub const Renderer = @import("Renderer.zig");

pub const Transform = nz.Transform3D(f32);
pub const Camera = @import("system/Camera.zig");
pub const Mesh = struct {
    id: u32,
};

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
        Mesh,
    }),
    enitity_mapping: std.AutoHashMap(u32, u32),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .mutex = .init,
            .ec = try .init(allocator, null),
            .enitity_mapping = .init(allocator),
        };
    }
    pub fn deinit(self: *@This()) void {
        self.ec.deinit();
        self.enitity_mapping.deinit();
    }
};

pub const Context = struct {
    asset_server: *AssetServer,
    renderer: Renderer,
    allocator: std.mem.Allocator,
    io: std.Io,
    network_manager: NetworkManager,

    pub const Data = struct {
        allocator: std.mem.Allocator,
        asset_server: *AssetServer,
        platform: yes.Platform,
        window: *yes.Window,
        stream: std.Io.net.Stream,
        io: std.Io,
        server_address: std.Io.net.IpAddress,
    };

    pub fn init(self: *@This(), data: Data) !void {
        self.* = .{
            .asset_server = data.asset_server,
            .renderer = try .init(data.allocator, data.asset_server, data.platform, data.window),
            .allocator = data.allocator,
            .io = data.io,
            .network_manager = .{ .stream = undefined, .server_address = undefined, .server_listen = undefined },
        };
        try self.network_manager.init(data.allocator, data.io, data.stream, data.server_address);
    }

    pub fn deinit(self: *@This()) !void {
        self.renderer.deinit(self.allocator);
        try self.network_manager.deinit();
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        var query = info.world.ec.query(&.{ Camera, nz.Transform3D(f32) });
        if (query.next()) |entry| {
            const camera = entry.getPtr(Camera, info.world.ec).?;
            const transform = entry.getPtr(nz.Transform3D(f32), info.world.ec).?;
            camera.update(info);
            try self.renderer.update(info);

            var fixed_writer_buffer: [1024]u8 = undefined;
            var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
            const writer = &fix_writer;
            const input_command: shared.net.Command = .{ .input = camera.input_map };
            try input_command.write(writer);
            try self.network_manager.stream.socket.send(self.io, &self.network_manager.server_address, writer.buffered());

            camera.transform.position = transform.position;
        }
        try self.asset_server.update();
        try self.network_manager.update(info);
    }

    pub fn eventUpdate(self: *@This(), info: *const Info, event: *const yes.Window.Event) !void {
        _ = self;
        var query = info.world.ec.query(&.{Camera});
        if (query.next()) |entry| {
            try entry.getPtr(Camera, info.world.ec).?.eventUpdate(info, event);
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
        context.init(data.*) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        std.log.debug("system context deinit", .{});
        context.deinit() catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
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
