const std = @import("std");
const shared = @import("shared");

pub fn main(init: std.process.Init) !void {
    std.debug.print("server\n", .{});

    const io = init.io;
    var server = try shared.net.address.listen(io, .{ .reuse_address = true, .mode = .stream });
    defer server.deinit(io);

    while (true) {
        const stream = try server.accept(io);

        _ = io.async(handleClient, .{ io, stream });
    }
}

pub fn handleClient(io: std.Io, stream: std.Io.net.Stream) !void {
    defer stream.close(io);

    var stream_writer_buffer: [128]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_writer_buffer);
    const writer = &stream_writer.interface;

    while (true) {
        try writer.print("Hello!", .{});
        try writer.flush();

        _ = try io.sleep(.fromMilliseconds(100), .real);
    }
}
