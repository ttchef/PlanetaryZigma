const std = @import("std");
const system = @import("system");
const shared = @import("shared");
const World = system.World;
const nz = shared.nz;

pub fn main(init: std.process.Init) !void {
    std.debug.print("server\n", .{});

    var gpa: std.heap.DebugAllocator(.{ .verbose_log = false, .safety = true }) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const io = init.io;
    const addr = try std.Io.net.IpAddress.parse("127.0.0.1", 8080);
    var socket = try addr.bind(io, .{ .protocol = .udp, .mode = .dgram });
    defer socket.close(io);

    var watcher: shared.Watcher = try .init("system_server_", io);
    defer watcher.deinit(io);
    try watcher.load(io);

    var system_context: system.Context = undefined;
    var system_table: system.ffi.Table = try .load(&watcher.dynlib.?);

    system_table.systemContextInit(&system_context, &system.Context.Data{
        .allocator = allocator,
    });
    defer system_table.systemContextDeinit(&system_context);

    var world: World = try .init(allocator);
    defer world.deinit();

    var accept_client_future = try io.concurrent(acceptClient, .{ io, &socket, &world });

    var count: usize = 0;
    var accumlated_time: f32 = 0;
    const time_step: f32 = 0.0167;
    while (true) {
        accumlated_time += getDeltaTime(io);
        if (accumlated_time < time_step) continue;
        accumlated_time -= time_step;
        try world.mutex.lock(io);
        count += 1;

        system_table.systemContextUpdate(&system_context, &.{ .delta_time = 1, .elapsed_time = 0, .world = &world });
        if (try watcher.reload(io)) {
            std.log.debug("system table updated", .{});
            watcher.old_dynlib.?.close();
            system_table = try .load(&watcher.dynlib.?);
            system_table.systemContextInit(&system_context, &system.Context.Data{
                .allocator = allocator,
            });
        }
        world.mutex.unlock(io);
    }
    try accept_client_future.await(io);
}

pub fn acceptClient(io: std.Io, socket: *std.Io.net.Socket, world: *World) !void {
    std.log.debug("hello 1", .{});
    var buffer: [1024]u8 = undefined;
    while (true) {
        const msg = try socket.receive(io, &buffer);
        _ = msg.from; // Sender's address
        _ = msg.data; // Received data (slice of buffer)
        _ = msg.flags;
        // TODO: Track clients by msg.from address
        // For UDP, you can respond with: server.socket.send(io, &msg.from, response_data)
        std.log.debug("hello {any}", .{msg.from});

        try world.mutex.lock(io);
        const entity_player = try world.ec.addEntity();
        entity_player.set(nz.Transform3D(f32), .{ .position = .{ 0, 20, 0 } }, world.ec);
        world.mutex.unlock(io);
    }
}

pub fn handleClient(io: std.Io, stream: std.Io.net.Stream, world: *World) !void {
    defer stream.close(io);

    var stream_writer_buffer: [128]u8 = undefined;
    var stream_writer = stream.writer(io, &stream_writer_buffer);
    const writer = &stream_writer.interface;

    try world.mutex.lock(io);
    const entity_player = try world.ec.addEntity();
    entity_player.set(nz.Transform3D(f32), .{ .position = .{ 0, 20, 0 } }, world.ec);
    world.mutex.unlock(io);

    while (true) {
        try writer.print("Hello!", .{});
        try writer.flush();

        _ = try io.sleep(.fromMilliseconds(100), .real);
    }
}

pub fn getDeltaTime(io: std.Io) f32 {
    const static = struct {
        var previous: ?std.Io.Timestamp = null;
    };

    const now: std.Io.Timestamp = .now(io, .real);
    const prev = static.previous orelse {
        static.previous = now;
        return getDeltaTime(io);
    };

    const dt_ns = prev.durationTo(now);
    static.previous = now;

    return @as(f32, @floatFromInt(dt_ns.nanoseconds)) / 1_000_000_000.0;
}
