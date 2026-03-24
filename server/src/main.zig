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
    var server = try shared.net.address.listen(io, .{
        .reuse_address = true,
        .mode = .stream,
    });
    defer server.deinit(io);

    var watcher: shared.Watcher = try .init("system_server_", io);
    defer watcher.deinit(io);
    try watcher.load(io);

    var system_context: system.Context = undefined;
    var system_table: system.ffi.Table = try .load(&watcher.dynlib.?);

    std.log.debug("ptr: {p}", .{system_table.systemContextInit});
    system_table.systemContextInit(&system_context, &system.Context.Data{
        .allocator = allocator,
    });
    defer system_table.systemContextDeinit(&system_context);

    var world: World = try .init(allocator);
    defer world.deinit();

    var accept_client_future = try io.concurrent(acceptClient, .{ io, &server, &world });

    var count: usize = 0;
    while (true) {
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

pub fn acceptClient(io: std.Io, server: *std.Io.net.Server, world: *World) !void {
    while (true) {
        const stream = try server.accept(io);
        _ = io.async(handleClient, .{ io, stream, world });
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
