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
    world: *World,
    io: std.Io,
    accept_client_future: std.Io.Future(@typeInfo(@TypeOf(net.Client.accept)).@"fn".return_type.?),
    socket: std.Io.net.Socket,
    clients: std.AutoHashMap(std.Io.net.IpAddress, net.Client),

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
            .clients = .init(data.allocator),
        };
        self.accept_client_future = try data.io.concurrent(net.Client.accept, .{ data.allocator, data.io, self.socket, &self.clients });
    }

    pub fn deinit(self: *@This()) !void {
        try self.accept_client_future.cancel(self.io);
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        const world = info.world;
        const dt = info.delta_time;
        var it = self.clients.iterator();
        while (it.next()) |pair| {
            const client = pair.value_ptr;
            const client_address = pair.key_ptr;
            try client.command_queue.mutex.lock(self.io);
            for (client.command_queue.commands.items) |command| {
                var fixed_writer_buffer: [1024]u8 = undefined;
                var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
                const writer = &fix_writer;
                switch (command) {
                    .connect => {
                        var entity = try world.ec.addEntity();
                        entity.set(nz.Transform3D(f32), .{}, world.ec);
                        client.entity_id = @intCast(@intFromEnum(entity));
                        const acknowledge_command: shared.net.Command = .{ .acknowledge = .{ .id = client.entity_id } };
                        try acknowledge_command.write(writer);
                        try self.socket.send(self.io, client_address, writer.buffered());
                        std.debug.print("enetiess : {d}: ID {d}\n", .{ world.ec.entity_count, client.entity_id });
                    },
                    .disconnect => {
                        try world.ec.remove(@enumFromInt(client.entity_id));
                        std.debug.print("enetiess : {d}\n", .{world.ec.entity_count});
                    },
                    .spawn_entity => {
                        try command.write(writer);
                        try self.socket.send(self.io, client_address, writer.buffered());
                    },
                    .input => {
                        const input = command.input;
                        var transform = world.ec.entityGetPtr(nz.Transform3D(f32), @enumFromInt(client.entity_id)).?;
                        const command_update_transform: shared.net.Command = .{ .update_transform = .{ .id = client.entity_id, .pos = transform.position } };
                        if (input.left) transform.position[0] -= dt;
                        if (input.right) transform.position[0] += dt;
                        if (input.up) transform.position[1] -= dt;
                        if (input.down) transform.position[1] += dt;
                        if (input.forward) {
                            transform.position[2] -= dt;
                            std.debug.print("client_address : {any}\n", .{client_address});
                        }

                        if (input.backward) transform.position[2] += dt;
                        try command_update_transform.write(writer);
                        try self.socket.send(self.io, client_address, writer.buffered());
                    },
                    else => {
                        std.log.err("Unhandled command {s}", .{@tagName(command)});
                    },
                }
            }
            client.command_queue.commands.clearAndFree(self.allocator);
            client.command_queue.mutex.unlock(self.io);
        }
    }
    fn reload(self: *@This(), pre_reload: bool) !void {
        if (pre_reload) try self.accept_client_future.cancel(self.io) else {
            self.accept_client_future = try self.io.concurrent(net.Client.accept, .{ self.allocator, self.io, self.socket, &self.clients });
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
