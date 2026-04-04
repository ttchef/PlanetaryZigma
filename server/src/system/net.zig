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
        self.command_queue.commands.deinit(self.allocator);
    }
};
