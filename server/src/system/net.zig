const std = @import("std");
const World = @import("../system.zig").World;
const shared = @import("shared");
const nz = shared.nz;

pub fn acceptClient(io: std.Io, socket: *std.Io.net.Socket, world: *World) !void {
    std.log.debug("hello 1", .{});
    var buffer: [shared.Net.data_size]u8 = undefined;
    while (true) {
        const msg = try socket.receive(io, &buffer);
        _ = msg.from; // Sender's address
        _ = msg.data; // Received data (slice of buffer)
        _ = msg.flags;
        var command: shared.Net.Command = undefined;
        const ptr = &command;
        const data = @as([*]u8, @ptrCast(ptr));
        @memcpy(data, msg.data);
        // TODO: Track clients by msg.from address
        // For UDP, you can respond with: server.socket.send(io, &msg.from, response_data)
        // std.log.debug("recived: id: {d}, data: {any}\nFrom  {any}", .{ command.id, command.data, msg.from });

        try world.mutex.lock(io);
        // const entity_player = try world.ec.addEntity();
        // entity_player.set(nz.Transform3D(f32), .{ .position = .{ 0, 20, 0 } }, world.ec);
        world.mutex.unlock(io);
    }
}
