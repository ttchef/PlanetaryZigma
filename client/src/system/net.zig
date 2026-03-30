const std = @import("std");
const shared = @import("shared");
const World = @import("../system.zig").World;

pub fn listen(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, commands: *std.ArrayList(shared.net.Command)) !void {
    std.log.debug("hello 1", .{});
    var buffer: [1024]u8 = undefined;
    while (true) {
        const msg = stream.socket.receive(io, &buffer) catch |err| {
            if (err == error.WouldBlock) continue;
            return err;
        };

        var msg_reader: std.Io.Reader = .fixed(&buffer);
        const reader = &msg_reader;
        std.log.debug("data: {any}", .{msg.data});

        const parsed = try shared.net.Command.parse(reader);

        try commands.append(allocator, parsed.command);
    }
}
