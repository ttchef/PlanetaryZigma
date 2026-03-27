const std = @import("std");
const World = @import("../system.zig").World;
const shared = @import("shared");
const nz = shared.nz;

pub fn acceptClient(io: std.Io, socket: *std.Io.net.Socket, world: *World) !void {
    std.log.debug("hello 1", .{});
    var buffer: [1024]u8 = undefined;
    while (true) {
        const msg = try socket.receive(io, &buffer);
        _ = msg.from; // Sender's address
        _ = msg.data; // Received data (slice of buffer)
        _ = msg.flags;
        const header, const connect, const size = try shared.net.cmd.readBuf(shared.net.cmd.Connect, &buffer);
        std.log.debug("LOLXD", .{});
        // var command: shared.Net.Command = undefined;
        // const ptr = &command;
        // const data = @as([*]u8, @ptrCast(ptr));
        // @memcpy(data, msg.data);
        // TODO: Track clients by msg.from address
        // For UDP, you can respond with: server.socket.send(io, &msg.from, response_data)
        std.log.debug("recived: header: {any}, connect: {any}, size: {d}", .{ header, connect, size });

        try world.mutex.lock(io);
        // const entity_player = try world.ec.addEntity();
        // entity_player.set(nz.Transform3D(f32), .{ .position = .{ 0, 20, 0 } }, world.ec);
        world.mutex.unlock(io);
    }
}
