const std = @import("std");
const World = @import("../system.zig").World;
const shared = @import("shared");
const nz = shared.nz;

pub const Client = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    entity_id: i32 = -1,
    command_queue: std.ArrayList(shared.net.Command) = .empty,

    pub fn accept(allocator: std.mem.Allocator, io: std.Io, address: std.Io.net.IpAddress, clients: *std.AutoHashMap(std.Io.net.IpAddress, @This())) !void {
        std.log.debug("hello 1", .{});
        var buffer: [1024]u8 = undefined;
        const socket = try address.bind(io, .{ .protocol = .udp, .mode = .dgram });

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
                    try client.command_queue.append(allocator, parsed.command);
                },
                else => {
                    var client = clients.getPtr(msg.from).?;
                    try client.command_queue.append(allocator, parsed.command);
                },
            }
        }
    }

    pub fn deinit(self: *@This()) !void {
        self.allocator.free(self.name);
        self.command_queue.deinit(self.allocator);
    }
};
