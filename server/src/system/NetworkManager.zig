const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const Spawner = @import("Spawner.zig");
const Info = system.Info;
const component = system.World.component;

gpa: std.mem.Allocator,
io: std.Io,
accept_client_future: std.Io.Future(@typeInfo(@TypeOf(Client.accept)).@"fn".return_type.?),
socket: std.Io.net.Socket,
clients: std.AutoHashMap(std.Io.net.IpAddress, Client),

pub const Client = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    server_socket: std.Io.net.Socket,
    name: []const u8,
    entity_id: u32 = 0,
    needs_full_sync: bool = true,
    command_queue: shared.net.CommandQueue = .{},
    ip_address: std.Io.net.IpAddress,

    pub fn accept(gpa: std.mem.Allocator, io: std.Io, socket: std.Io.net.Socket, clients: *std.AutoHashMap(std.Io.net.IpAddress, @This())) !void {
        var buffer: [1024]u8 = undefined;
        while (true) {
            const msg = try socket.receive(io, &buffer);
            _ = msg.from; // Sender's address
            _ = msg.data; // Received data (slice of buffer)
            _ = msg.flags;

            var msg_reader: std.Io.Reader = .fixed(&buffer);
            const reader = &msg_reader;

            const parsed = try shared.net.Command.parse(reader);
            // std.log.debug("Spanned: {any}", .{parsed.command});

            if (parsed.command == .connect) {
                const connect = parsed.command.connect;
                try clients.put(msg.from, undefined);
                const client = clients.getPtr(msg.from).?;
                client.* = .{
                    .gpa = gpa,
                    .io = io,
                    .server_socket = socket,
                    .name = try gpa.dupe(u8, connect.name),
                    .ip_address = msg.from,
                };
            }

            var client = clients.getPtr(msg.from).?;
            try client.command_queue.mutex.lock(io);
            try client.command_queue.commands.append(gpa, parsed.command);
            client.command_queue.mutex.unlock(io);
        }
    }

    pub fn sendCommand(self: *@This(), writer: *std.Io.Writer, command: shared.net.Command) !void {
        writer.end = 0;
        try command.write(writer);
        try self.server_socket.send(self.io, &self.ip_address, writer.buffer);
    }

    pub fn deinit(self: *@This()) !void {
        self.gpa.free(self.name);
        self.command_queue.deinit(self.gpa, self.io);
    }
};

pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io) !void {
    self.* = .{
        .gpa = gpa,
        .io = io,
        .socket = try shared.net.address.bind(io, .{ .protocol = .udp, .mode = .dgram }),
        .clients = .init(gpa),
        .accept_client_future = try io.concurrent(Client.accept, .{ gpa, io, self.socket, &self.clients }),
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
        self.accept_client_future = try self.io.concurrent(Client.accept, .{ self.gpa, self.io, self.socket, &self.clients });
    }
}

pub fn update(self: *@This(), info: *const Info, spawner: *Spawner) !void {
    const world = info.world;

    var fixed_writer_buffer: [1024]u8 = undefined;
    var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
    const writer = &fix_writer;

    // var clients_to_remove: std.ArrayList(struct { ip: *std.Io.net.IpAddress, client: *Client }) = .empty;

    var it = self.clients.iterator();
    while (it.next()) |pair| {
        const client = pair.value_ptr;
        // const client_address = pair.key_ptr;
        try client.command_queue.mutex.lock(self.io);

        for (client.command_queue.commands.items) |command| {
            switch (command) {
                .connect => {
                    std.log.debug("connect ", .{});
                    client.entity_id = try spawner.spawnConnectPlayer();
                    try client.sendCommand(writer, .{ .acknowledge = .{ .id = client.entity_id } });
                    std.debug.print("enetiess : {d}: ID {d}\n", .{ world.ecz.last_id, client.entity_id });
                },
                .disconnect => {
                    std.debug.print("enteties in ECS : {d}\n", .{world.ecz.last_id});
                    try spawner.depspawn(client.entity_id);
                    // const entity_to_remove = @TypeOf(world.ecz).Entity.fromId(&world.ecz, client.entity_id);
                    // try entity_to_remove.despawn();
                    // try self.pending_despawn.append(self.gpa, .{ .id = entity_to_remove.id, .entity_type = .player });
                    // try clients_to_remove.append(self.allocator, .{ .ip = client_address, .client = client });
                },
                .input => {
                    const input_entity = @TypeOf(world.ecz).Entity.fromId(&world.ecz, client.entity_id);
                    const input = input_entity.getComponentPtr(component.input);
                    input.* = command.input;
                    // std.debug.print("mouse :{any}\n", .{input.*.mouse_delta});
                },
                else => {
                    std.log.err("Unhandled command {s}", .{@tagName(command)});
                },
            }
        }
        client.command_queue.commands.items.len = 0;
        // if (update_game_state == true) {
        //     std.debug.print("SEND enteties in ECS : {d}\n", .{world.ecz.last_id});
        //     var query = world.ecz.query(&.{component.transform});
        //     while (query.next()) |entity| {
        //         if (client.entity_id == entity.id) continue;
        //         std.debug.print("ent in ecs ID {d}\n", .{entity.id});
        //         writer.end = 0;
        //         const spawn_entitiy_cmd: shared.net.Command = .{ .spawn_entity = .{ .id = entity.id } };
        //         try client.command_queue.commands.append(self.allocator, spawn_entitiy_cmd);
        //     }
        // }
        // writer.end = 0;
        // const xentity = @TypeOf(world.ecz).Entity.fromId(&world.ecz, client.entity_id);
        // var xtransform = xentity.getComponentPtr(component.transform);
        // var xcommand_update_transform: shared.net.Command = .{ .update_transform = .{ .id = client.entity_id, .pos = xtransform.position } };
        // xcommand_update_transform.update_transform.id = client.entity_id;
        // xtransform.position += .{ 0, 0, -1 };
        // xcommand_update_transform.update_transform.pos = xtransform.position;
        // try xcommand_update_transform.write(writer);
        // try self.socket.send(self.io, client_address, writer.buffered());

        client.command_queue.mutex.unlock(self.io);
    }

    it = self.clients.iterator();
    while (it.next()) |pair| {
        const client = pair.value_ptr;

        //update camera
        const player_entity = world.ecz.entityFromId(client.entity_id);
        const camera = player_entity.getComponent(component.camera);
        try client.sendCommand(writer, .{ .update_camera_rotation = .{ .position = camera.transform.position, .rotation = camera.transform.rotation.toVec(), .id = client.entity_id } });

        //ECS spawns
        if (client.needs_full_sync) {
            var query = world.ecz.query(&.{ component.transform, component.entity_type });

            while (query.next()) |entity| {
                std.log.debug("sent id {d}", .{entity.id});
                const entity_type = entity.getComponent(component.entity_type);
                var data: [4]u8 = @splat(0);
                switch (entity_type) {
                    .planet => {
                        const planet = entity.getComponent(component.planet);
                        data = @bitCast(planet);
                    },
                    else => {},
                }
                try client.sendCommand(writer, .{ .spawn_entity = .{
                    .id = entity.id,
                    .entity_type = entity_type,
                    .data = data,
                } });
                // const entity_type = entity.getComponent(component.entity_type);
                // try client.sendCommand(writer, .{ .spawn_entity = .{ .id = entity.id, .entity_type = entity_type } });
            }
            client.needs_full_sync = false;
        } else {
            // std.debug.print("SEND enteties in ECS : {d}\n", .{world.ecz.last_id});
            for (spawner.network_pending_spawn.items) |entry| {
                try client.sendCommand(writer, .{ .spawn_entity = .{ .id = entry.id, .entity_type = entry.entity_type } });
            }
        }
        //ECS despawns
        for (spawner.network_pending_despawn.items) |id| {
            try client.sendCommand(writer, .{ .despawn_entity = .{ .id = id } });
        }
        //Update ECS Transforms
        var query = world.ecz.query(&.{component.transform});
        while (query.next()) |entity| {
            const transform = entity.getComponent(component.transform);
            try client.sendCommand(writer, .{ .update_transform = .{
                .id = entity.id,
                .position = transform.position,
                .rotation = transform.rotation.toVec(),
            } });
        }
    }
    spawner.network_pending_spawn.items.len = 0;
    spawner.network_pending_despawn.items.len = 0;

    // for (clients_to_remove.items) |client| {
    //     _ = self.clients.remove(client.ip.*);
    // }
    // for (clients_to_remove.items) |client| {
    //     writer.end = 0;
    //     try client.client.command_queue.mutex.lock(self.io);
    //     const remove_entity_cmd: shared.net.Command = .{ .despawn_entity = .{ .id = client.client.entity_id } };
    //     try remove_entity_cmd.write(writer);
    //     try self.socket.send(self.io, client.ip, writer.buffered());
    //     client.client.command_queue.mutex.unlock(self.io);
    // }
}
