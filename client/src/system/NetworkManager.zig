const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const World = system.World;
const Info = system.Info;
const nz = shared.nz;

stream: std.Io.net.Stream,
server_address: std.Io.net.IpAddress,
server_listen: std.Io.Future(@typeInfo(@TypeOf(listen)).@"fn".return_type.?),
command_queue: shared.net.CommandQueue = .{},
io: std.Io = undefined,
allocator: std.mem.Allocator = undefined,

pub fn init(self: *@This(), allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, server_address: std.Io.net.IpAddress) !void {
    self.server_listen = try io.concurrent(listen, .{ allocator, io, stream, &self.command_queue });
    self.stream = stream;
    self.server_address = server_address;
    self.io = io;
    self.allocator = allocator;
}

pub fn deinit(self: *@This()) !void {
    try self.server_listen.cancel(self.io);
    // self.enitity_mapping.deinit();
}

pub fn listen(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, command_queue: *shared.net.CommandQueue) !void {
    std.log.debug("hello 1", .{});
    var buffer: [1024]u8 = undefined;
    while (true) {
        const msg = stream.socket.receive(io, &buffer) catch |err| {
            if (err == error.WouldBlock) continue;
            return err;
        };
        _ = msg;

        var msg_reader: std.Io.Reader = .fixed(&buffer);
        const reader = &msg_reader;

        const parsed = try shared.net.Command.parse(reader);

        if (parsed.command == .update_transform) {
            std.log.debug("Data: {any}", .{parsed.command});
        }

        try command_queue.mutex.lock(io);
        try command_queue.commands.append(allocator, parsed.command);
        command_queue.mutex.unlock(io);
    }
}

pub fn update(self: *@This(), info: *const Info) !void {
    try self.command_queue.mutex.lock(self.io);
    for (self.command_queue.commands.items) |command| {
        switch (command) {
            .acknowledge => {
                var new_camera = try info.world.ec.addEntity();
                new_camera.set(system.Camera, .{ .transform = .{ .position = .{ 0, 0, 0 } } }, info.world.ec);
                new_camera.set(nz.Transform3D(f32), .{ .position = .{ 0, 0, 40 } }, info.world.ec);
                try info.world.enitity_mapping.put(command.acknowledge.id, @intCast(@intFromEnum(new_camera)));
                std.debug.print("ack enetiess : {d}\n", .{info.world.ec.entity_count});
                std.debug.print("MY ID: {d}, server ID: {d} ", .{ @intFromEnum(new_camera), command.acknowledge.id });
            },
            .spawn_entity => {
                var new_entity = try info.world.ec.addEntity();
                new_entity.set(nz.Transform3D(f32), .{ .position = .{ 0, 0, 0 } }, info.world.ec);
                new_entity.set(system.Mesh, .{ .id = 0 }, info.world.ec);
                try info.world.enitity_mapping.put(command.spawn_entity.id, @intCast(@intFromEnum(new_entity)));
                std.debug.print("spawn enetiess : {d}\n", .{info.world.ec.entity_count});
            },
            .update_transform => {
                const update_transform_command = command.update_transform;
                std.log.debug("server ID: {d},  ", .{update_transform_command.id});
                const id = info.world.enitity_mapping.get(update_transform_command.id);
                if (id == null) continue;
                std.log.debug("MY ID: {d},  ", .{update_transform_command.id});
                const transform = info.world.ec.entityGetPtr(nz.Transform3D(f32), @enumFromInt(id.?));
                if (transform) |t| t.position = update_transform_command.pos;
            },
            else => {
                std.log.err("Unhandled command {s}", .{@tagName(command)});
            },
        }
    }
    self.command_queue.commands.clearAndFree(self.allocator);
    self.command_queue.mutex.unlock(self.io);
}
