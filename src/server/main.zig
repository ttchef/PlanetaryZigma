const std = @import("std");
const System = @import("System");
const shared = @import("shared");
const World = shared.World;
const nz = shared.nz;

pub fn main(init: std.process.Init) !void {
    std.debug.print("server\n", .{});

    var gpa: std.heap.DebugAllocator(.{ .verbose_log = false, .safety = true }) = .init;
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const io = init.io;
    var server = try shared.net.address.listen(io, .{
        .reuse_address = true,
        .mode = .stream,
    });
    defer server.deinit(io);

    var system_watcher: shared.Watcher = try .init("libsystem{s}", io);
    var systems: System = undefined;
    var systemsInit = try system_watcher.lookup(System.InitSystems, "initSystems");
    var systemsDeinit = try system_watcher.lookup(System.DeinitSystems, "deinit");
    var systemsUpdate = try system_watcher.lookup(System.UpdateSystems, "update");

    var world: World = try .init(allocator);
    defer world.deinit();
    if (systemsInit(&systems, &allocator) != 0) return error.SystemsInit;
    defer systemsDeinit(&systems, &allocator);

    var accept_client_future = try io.concurrent(acceptClient, .{ io, &server, &world });

    var count: usize = 0;
    while (true) {
        try world.mutex.lock(io);
        count += 1;

        std.debug.print("eneties: {d}\n", .{world.ec.generation.items.len});
        systemsUpdate(&systems, 1.0);
        if (try system_watcher.reload(io)) {
            systemsDeinit(&systems, &allocator);

            systemsInit = try system_watcher.lookup(System.InitSystems, "initSystems");
            systemsDeinit = try system_watcher.lookup(System.DeinitSystems, "deinit");
            systemsUpdate = try system_watcher.lookup(System.UpdateSystems, "update");
            if (systemsInit(&systems, &allocator) != 0) return error.SystemsInit;
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
