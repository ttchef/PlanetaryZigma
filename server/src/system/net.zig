const std = @import("std");
const shared = @import("shared");
const nz = shared.nz;

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
            std.log.debug("data: {any}", .{msg.data});

            const parsed = try shared.net.Command.parse(reader);

            switch (parsed.command) {
                .connect => {
                    const connect = parsed.command.connect;
                    std.log.debug("recived {any}", .{parsed.command});
                    std.log.debug("PHASE 0", .{});
                    try clients.put(msg.from, undefined);
                    var client = clients.getPtr(msg.from).?;

                    std.log.debug("PHASE 1", .{});
                    client.* = .{
                        .allocator = allocator,
                        .name = try allocator.dupe(u8, connect.name),
                    };
                    try client.command_queue.commands.append(allocator, parsed.command);
                    // var fixed_writer_buffer: [1024]u8 = undefined;
                    // var fix_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
                    // const writer = &fix_writer;
                    // try spawn_entitiy_cmd.write(writer);
                    // const client_address = pair.key_ptr;
                    // try socket.send(io, client_address, writer.buffered());

                    const spawn_entitiy_cmd: shared.net.Command = .{ .spawn_entity = .{ .id = 0 } };
                    var it = clients.iterator();
                    while (it.next()) |pair| {
                        if (pair.key_ptr.*.eql(&msg.from)) continue;
                        const it_client = pair.value_ptr;
                        try it_client.command_queue.commands.append(allocator, spawn_entitiy_cmd);
                        const it_spawn_entitiy_cmd: shared.net.Command = .{ .spawn_entity = .{ .id = @intCast(it_client.entity_id) } };
                        try client.command_queue.commands.append(allocator, it_spawn_entitiy_cmd);
                    }
                },
                else => {
                    var client = clients.getPtr(msg.from).?;
                    try client.command_queue.commands.append(allocator, parsed.command);
                },
            }
        }
    }

    pub fn deinit(self: *@This()) !void {
        self.allocator.free(self.name);
        self.command_queue.commands.deinit(self.allocator);
    }
};
