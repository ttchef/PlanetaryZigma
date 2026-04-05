const std = @import("std");
const shared = @import("shared");
const Info = @import("../system.zig").Info;
const nz = shared.nz;

accept_client_future: std.Io.Future(@typeInfo(@TypeOf(Client.accept)).@"fn".return_type.?),
socket: std.Io.net.Socket,
clients: std.AutoHashMap(std.Io.net.IpAddress, Client),
io: std.Io,
allocator: std.mem.Allocator,

pub const Client = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    entity_id: u32 = 0,
    command_queue: shared.net.CommandQueue = .{},

    pub fn accept(allocator: std.mem.Allocator, io: std.Io, socket: std.Io.net.Socket, clients: *std.AutoHashMap(std.Io.net.IpAddress, @This())) !void {
        std.log.debug("hello 1", .{});
        var buffer: [1024]u8 = undefined;
        while (true) {
            const msg = try socket.receive(io, &buffer);
            _ = msg.from; // Sender's address
            _ = msg.data; // Received data (slice of buffer)
            _ = msg.flags;

            var msg_reader: std.Io.Reader = .fixed(&buffer);
            const reader = &msg_reader;

            const parsed = try shared.net.Command.parse(reader);

            if (parsed.command == .connect) {
                const connect = parsed.command.connect;
                try clients.put(msg.from, undefined);
                const client = clients.getPtr(msg.from).?;
                client.* = .{
                    .allocator = allocator,
                    .name = try allocator.dupe(u8, connect.name),
                };
            }

            var client = clients.getPtr(msg.from).?;
            try client.command_queue.mutex.lock(io);
            try client.command_queue.commands.append(allocator, parsed.command);
            client.command_queue.mutex.unlock(io);
        }
    }

    pub fn deinit(self: *@This()) !void {
        self.allocator.free(self.name);
        self.command_queue.deinit(self.allocator, self.io);
    }
};

pub fn init(self: *@This(), allocator: std.mem.Allocator, io: std.Io) !void {
    const address = try std.Io.net.IpAddress.parse(shared.net.server_ip, shared.net.server_port);
    self.* = .{
        .allocator = allocator,
        .io = io,
        .socket = try address.bind(io, .{ .protocol = .udp, .mode = .dgram }),
        .clients = .init(allocator),
        .accept_client_future = try io.concurrent(Client.accept, .{ allocator, io, self.socket, &self.clients }),
    };
}

pub fn deinit(self: *@This()) !void {
    self.accept_client_future.cancel(self.io) catch |err| {
        switch (err) {
            error.Canceled => std.log.err("err: {s}", .{@errorName(err)}),
            error.Unexpected => std.log.err("err: {s}", .{@errorName(err)}),
            else => {
                std.log.err("err: {s}", .{@errorName(err)});
                return err;
            },
        }
    };
}

pub fn reload(self: *@This(), pre_reload: bool) !void {
    if (pre_reload) try self.accept_client_future.cancel(self.io) else {
        std.log.debug("RELOAD", .{});
        self.accept_client_future = try self.io.concurrent(Client.accept, .{ self.allocator, self.io, self.socket, &self.clients });
    }
}

pub fn update(self: *@This(), info: *const Info) !void {
    var update_game_state: bool = false;
    const world = info.world;
    const dt = info.delta_time;

    var fixed_writer_buffer: [1024]u8 = undefined;
    var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
    const writer = &fix_writer;

    var clients_to_remove: std.ArrayList(struct { ip: *std.Io.net.IpAddress, client: *Client }) = .empty;

    var it = self.clients.iterator();
    while (it.next()) |pair| {
        const client = pair.value_ptr;
        const client_address = pair.key_ptr;
        try client.command_queue.mutex.lock(self.io);

        for (client.command_queue.commands.items) |command| {
            writer.end = 0;
            switch (command) {
                .connect => {
                    update_game_state = true;
                    std.debug.print("connect ", .{});
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
                    std.debug.print("enteties in ECS : {d}\n", .{world.ec.entity_count});
                    try clients_to_remove.append(self.allocator, .{ .ip = client_address, .client = client });
                },
                .spawn_entity => {
                    try command.write(writer);
                    try self.socket.send(self.io, client_address, writer.buffered());
                },
                .input => {
                    const input = command.input;
                    var transform = world.ec.entityGetPtr(nz.Transform3D(f32), @enumFromInt(client.entity_id)).?;

                    if (input.left) transform.position[0] -= dt;
                    // if (input.left) {
                    //     transform.position = .{ 0, 0, 100 };
                    // }
                    if (input.right) transform.position[0] += dt;
                    if (input.up) transform.position[1] -= dt;
                    if (input.down) transform.position[1] += dt;
                    if (input.forward) transform.position[2] -= dt;
                    if (input.backward) transform.position[2] += dt;
                },
                else => {
                    std.log.err("Unhandled command {s}", .{@tagName(command)});
                },
            }
        }
        client.command_queue.commands.items.len = 0;
        if (update_game_state == true) {
            std.debug.print("SEND enteties in ECS : {d}\n", .{world.ec.entity_count});
            var query = world.ec.query(&.{nz.Transform3D(f32)});
            while (query.next()) |entry| {
                const id = @intFromEnum(entry);
                if (client.entity_id == id) continue;
                std.debug.print("ent in ecs ID {d}\n", .{id});
                writer.end = 0;
                const spawn_entitiy_cmd: shared.net.Command = .{ .spawn_entity = .{ .id = @intCast(id) } };
                try client.command_queue.commands.append(self.allocator, spawn_entitiy_cmd);
            }
        }
        // writer.end = 0;
        // var xtransform = world.ec.entityGetPtr(nz.Transform3D(f32), @enumFromInt(client.entity_id)).?;
        // var xcommand_update_transform: shared.net.Command = .{ .update_transform = .{ .id = client.entity_id, .pos = xtransform.position } };
        // xcommand_update_transform.update_transform.id = client.entity_id;
        // xtransform.position += .{ 0, 0, -1 };
        // xcommand_update_transform.update_transform.pos = xtransform.position;
        // try xcommand_update_transform.write(writer);
        // try self.socket.send(self.io, client_address, writer.buffered());

        client.command_queue.mutex.unlock(self.io);
        var query = world.ec.query(&.{nz.Transform3D(f32)});
        while (query.next()) |entry| {
            writer.end = 0;
            // std.log.debug("Transform Entry ID {d}", .{@intFromEnum(entry)});

            const transform = entry.get(nz.Transform3D(f32), world.ec).?;
            const command_update_transform: shared.net.Command = .{ .update_transform = .{ .id = @intCast(@intFromEnum(entry)), .pos = transform.position } };
            try command_update_transform.write(writer);
            try self.socket.send(self.io, client_address, writer.buffered());
        }
    }
    for (clients_to_remove.items) |client| {
        _ = self.clients.remove(client.ip.*);
    }
    for (clients_to_remove.items) |client| {
        writer.end = 0;
        try client.client.command_queue.mutex.lock(self.io);
        const remove_entity_cmd: shared.net.Command = .{ .despawn_entity = .{ .id = client.client.entity_id } };
        try remove_entity_cmd.write(writer);
        try self.socket.send(self.io, client.ip, writer.buffered());
        client.client.command_queue.mutex.unlock(self.io);
    }
}
