const std = @import("std");
const System = @import("System");
const shared = @import("shared");

pub fn main(init: std.process.Init) !void {
    std.debug.print("server\n", .{});

    var gpa: std.heap.DebugAllocator(.{ .verbose_log = false, .safety = true }) = .init;
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const io = init.io;
    var server = try shared.net.address.listen(io, .{ .reuse_address = true, .mode = .stream });
    defer server.deinit(io);

    var system_watcher: shared.Watcher = try .init("libsystem{s}", io);
    var systems: System = undefined;
    const systemsInit = try system_watcher.lookup(System.InitSystems, "initSystems");
    // var systemsUpdate = try system_watcher.lookup(System.UpdateSystems, "update");
    const systemsDeinit = try system_watcher.lookup(System.DeinitSystems, "deinit");
    // var systemsReload = try system_watcher.lookup(System.ReloadSystems, "reload");
    if (systemsInit(&systems, &allocator) != 0) return error.SystemsInit;
    defer systemsDeinit(&systems, &allocator);

    while (true) {
        std.debug.print("jello\n", .{});
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
