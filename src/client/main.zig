const std = @import("std");
const shared = @import("shared");

pub fn main(init: std.process.Init) !void {
    std.debug.print("client\n", .{});
    const io = init.io;
    _ = try io.sleep(.fromSeconds(1), .real);
    const stream = try shared.net.address.connect(io, .{ .mode = .stream });
    defer stream.close(io);

    var stream_reader_buffer: [128]u8 = undefined;
    var stream_reader = stream.reader(io, &stream_reader_buffer);
    const reader = &stream_reader.interface;

    while (true) {
        reader.fillMore() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const read = reader.buffered();

        std.debug.print("from server: {s}\n", .{read});

        reader.tossBuffered();
    }
}
