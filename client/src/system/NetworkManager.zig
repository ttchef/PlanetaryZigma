const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const component = system.component;
const World = system.World;
const Info = system.Info;

gpa: std.mem.Allocator,
io: std.Io,
stream: std.Io.net.Stream,
server_address: std.Io.net.IpAddress,
server_listen: std.Io.Future(@typeInfo(@TypeOf(listen)).@"fn".return_type.?),
command_queue: shared.net.CommandQueue = .{},

pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, server_address: std.Io.net.IpAddress) !void {
    self.* = .{
        .gpa = gpa,
        .io = io,
        .stream = stream,
        .server_address = server_address,
        .server_listen = try io.concurrent(listen, .{ gpa, io, stream, &self.command_queue }),
    };
}

pub fn deinit(self: *@This()) !void {
    self.server_listen.cancel(self.io) catch |err| {
        switch (err) {
            error.Canceled => std.log.err("err: {s}", .{@errorName(err)}),
            error.Unexpected => std.log.err("err: {s}", .{@errorName(err)}),
            else => {
                std.log.err("err: {s}", .{@errorName(err)});
                return err;
            },
        }
    };
    try self.command_queue.deinit(self.gpa, self.io);
}

pub fn listen(gpa: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, command_queue: *shared.net.CommandQueue) !void {
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

        if (parsed.command == .spawn_entity) {
            std.log.debug("Spanned: {any}", .{parsed.command});
        }

        try command_queue.mutex.lock(io);
        try command_queue.commands.append(gpa, parsed.command);
        command_queue.mutex.unlock(io);
    }
}

pub fn update(self: *@This(), info: *const Info) !void {
    var fixed_writer_buffer: [1024]u8 = undefined;
    var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
    const writer = &fix_writer;
    var query = info.world.ecz.query(&.{ component.camera, component.transform });
    if (query.next()) |entity| {
        const camera = entity.getComponentPtr(component.camera);
        try self.sendCommand(writer, .{ .input = camera.input_map });
    }
    try self.command_queue.mutex.lock(self.io);
    for (self.command_queue.commands.items) |command| {
        switch (command) {
            .acknowledge => {
                var new_camera = try info.world.ecz.spawnEntity();
                try new_camera.putComponent(component.camera, .{ .transform = .{ .position = .{ 0, 0, 0 } } });
                try new_camera.putComponent(component.transform, .{ .position = .{ 0, 0, 40 } });
                try info.world.enitity_mapping.put(self.gpa, command.acknowledge.id, new_camera.id);
                info.world.my_server_id = command.acknowledge.id;
                std.log.debug("ack entities: {d}", .{info.world.ecz.last_id});
                std.log.debug("ACK: MY ID: {d}, server ID: {d} ", .{ new_camera.id, command.acknowledge.id });
            },
            .spawn_entity => {
                const server_id = command.spawn_entity.id;
                if (info.world.enitity_mapping.contains(server_id)) continue; //TODO: maybe dont send entities that exists already?
                var new_entity = try info.world.ecz.spawnEntity();
                try new_entity.putComponent(component.transform, .{ .position = .{ 0, 0, 0 } });
                try new_entity.putComponent(component.mesh, .{ .id = 0 });
                try info.world.enitity_mapping.put(self.gpa, command.spawn_entity.id, new_entity.id);
                std.log.debug("spawn entities : {d}", .{info.world.ecz.last_id});
                std.log.debug("SPAWNED: MY ID: {d}, server ID: {d} ", .{ new_entity.id, command.spawn_entity.id });
            },
            .despawn_entity => {
                const server_id = command.despawn_entity.id;
                const my_id = info.world.enitity_mapping.get(command.despawn_entity.id) orelse {
                    std.log.debug("FAILED TO GET- SERVER ID: {d},  ", .{server_id});
                    continue;
                };
                const entity = info.world.ecz.entityFromId(my_id);
                try entity.despawn();
                std.log.debug("DESPAWNED: MY ID: {d}, server ID: {d} ", .{ my_id, server_id });
            },
            .update_transform => {
                const update_transform_command = command.update_transform;
                // std.log.debug("server ID: {d},  ", .{update_transform_command.id});
                const id = info.world.enitity_mapping.get(update_transform_command.id);
                if (id == null) {
                    // std.log.debug("FAILED TO GET- SERVER ID: {d},  ", .{update_transform_command.id});

                    continue;
                }

                // std.log.debug("MY ID: {d},  ", .{update_transform_command.id});
                const entity = @TypeOf(info.world.ecz).Entity.fromId(&info.world.ecz, id.?);
                const transform = entity.getComponentPtr(component.transform);

                transform.position = update_transform_command.position;
                transform.rotation = .fromVec(update_transform_command.rotation);
                // std.log.debug("update rot {any},  ", .{transform.rotation});
            },
            .update_camera_rotation => {
                const rotation_command = command.update_camera_rotation;
                // std.log.debug("server ID: {d},  ", .{update_transform_command.id});
                const id = info.world.enitity_mapping.get(rotation_command.id);
                if (id == null) {
                    // std.log.debug("FAILED TO GET- SERVER ID: {d},  ", .{update_transform_command.id});

                    continue;
                }

                // std.log.debug("MY ID: {d},  ", .{update_transform_command.id});
                const entity = @TypeOf(info.world.ecz).Entity.fromId(&info.world.ecz, id.?);
                const camera = entity.getComponentPtr(component.camera);
                // _ = camera;
                camera.transform.rotation = .fromVec(rotation_command.rotation);
                std.log.debug("update rot {any},  ", .{rotation_command.rotation});
            },
            else => {
                std.log.err("Unhandled command {s}", .{@tagName(command)});
            },
        }
    }
    // self.command_queue.commands.clearAndFree(self.allocator);
    self.command_queue.commands.items.len = 0;
    self.command_queue.mutex.unlock(self.io);
}
pub fn sendCommand(self: @This(), writer: *std.Io.Writer, command: shared.net.Command) !void {
    writer.end = 0;
    try command.write(writer);
    try self.stream.socket.send(self.io, &self.server_address, writer.buffer);
}
