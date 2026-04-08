const std = @import("std");
const shared = @import("shared");
const nz = shared.numz;
const yes = @import("yes");
pub const ecz = shared.ecz;
const NetworkManager = @import("system/NetworkManager.zig");
const AssetServer = @import("shared").AssetServer;
pub const Renderer = @import("Renderer.zig");

pub const Camera = @import("system/Camera.zig");
pub const Mesh = struct {
    id: u32,
};

pub const Info = struct {
    delta_time: f32,
    elapsed_time: f32,
    world: *World,
};

pub const component = struct {
    pub const transform: ecz.Component = .{ .name = .transform, .type = nz.Transform3D(f32) };
    pub const camera: ecz.Component = .{ .name = .camera, .type = Camera };
    pub const mesh: ecz.Component = .{ .name = .mesh, .type = Mesh };
};

pub const World = struct {
    mutex: std.Io.Mutex = .init,
    ecz: ecz.World(&.{
        component.transform,
        component.camera,
        component.mesh,
    }),
    enitity_mapping: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    my_server_id: u32 = 0,

    pub fn init(gpa: std.mem.Allocator) !@This() {
        return .{ .ecz = .init(gpa) };
    }
    pub fn deinit(self: *@This()) void {
        self.ecz.deinit();
        self.enitity_mapping.deinit(self.ecz.gpa);
    }
};

pub const Context = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    asset_server: *AssetServer,
    renderer: Renderer,
    network_manager: NetworkManager,

    pub const Data = struct {
        gpa: std.mem.Allocator,
        io: std.Io,
        asset_server: *AssetServer,
        platform: yes.Platform,
        window: *yes.Window,
        stream: std.Io.net.Stream,
        server_address: std.Io.net.IpAddress,
    };

    pub fn init(self: *@This(), data: Data) !void {
        self.* = .{
            .gpa = data.gpa,
            .io = data.io,
            .asset_server = data.asset_server,
            .renderer = try .init(data.gpa, data.asset_server, data.platform, data.window),
            .network_manager = undefined,
        };
        try self.network_manager.init(data.gpa, data.io, data.stream, data.server_address);
    }

    pub fn deinit(self: *@This()) !void {
        self.renderer.deinit(self.gpa);
        try self.network_manager.deinit();
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        var query = info.world.ecz.query(&.{ component.camera, component.transform });
        if (query.next()) |entity| {
            const camera = entity.getComponentPtr(component.camera);
            const transform = entity.getComponentPtr(component.transform);
            camera.update(info);
            try self.renderer.update(info);

            var fixed_writer_buffer: [1024]u8 = undefined;
            var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
            const writer = &fix_writer;
            const input_command: shared.net.Command = .{ .input = camera.input_map };
            try input_command.write(writer);
            try self.network_manager.stream.socket.send(self.io, &self.network_manager.server_address, writer.buffered());

            // std.log.debug("pos {any},  ", .{transform.position});
            camera.transform.position = transform.position;
        }
        try self.asset_server.update();
        try self.network_manager.update(info);
    }

    pub fn eventUpdate(self: *@This(), info: *const Info, event: *const yes.Window.Event) !void {
        _ = self;
        var query = info.world.ecz.query(&.{component.camera});
        if (query.next()) |entity| {
            try entity.getComponentPtr(component.camera).eventUpdate(info, event);
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
