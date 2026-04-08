const std = @import("std");
const builtin = @import("builtin");
const shared = @import("shared");
const system = @import("system");
const World = system.World;
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    var gpa_impl = if (builtin.mode == .Debug) std.heap.DebugAllocator(.{ .verbose_log = true }).init else init.gpa;
    defer {
        if (builtin.mode == .Debug) _ = gpa_impl.deinit();
    }
    const gpa = gpa_impl.allocator();
    const io = init.io;

    const addr: std.Io.net.IpAddress = try .parse("127.0.0.1", 8080);
    var stream = try addr.connect(io, .{ .mode = .dgram, .protocol = .udp });
    defer stream.close(io);

    var cross_platform: yes.Platform.Cross = try .init(gpa, io, init.minimal);
    defer cross_platform.deinit();
    const platform = cross_platform.platform();

    var cross_window: yes.Platform.Cross.Window = .empty(platform);
    const window = cross_window.interface(platform);
    try window.open(platform, .{
        .title = "PlanetaryZigma",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
        .surface_type = .vulkan,
    });
    defer window.close(platform);

    var asset_server = try shared.AssetServer.init(gpa, init.io);
    defer asset_server.deinit();

    var world: World = try .init(gpa);
    defer world.deinit();

    var watcher: shared.Watcher = try .init("system_client_", io);
    defer watcher.deinit(io);
    try watcher.load(io);

    var system_context: system.Context = undefined;
    var system_table: system.ffi.Table = try .load(&watcher.dynlib.?);

    system_table.systemContextInit(&system_context, &system.Context.Data{
        .gpa = gpa,
        .asset_server = &asset_server,
        .platform = platform,
        .window = window,
        .stream = stream,
        .io = io,
        .server_address = addr,
    });

    //TODO: Intial connect: move out.
    const name = "lucas";
    const connect_command: shared.net.Command = .{ .connect = .{
        .name_len = name.len,
        .name = name,
    } };
    var fixed_writer_buffer: [1024]u8 = undefined;
    var fixed_writer: std.Io.Writer = .fixed(&fixed_writer_buffer);
    const writer = &fixed_writer;
    try connect_command.write(writer);
    std.log.debug("buffer: {any}", .{writer.buffered()});
    try stream.socket.send(io, &system_context.network_manager.server_address, writer.buffered());

    var elapsed_time: f32 = 0;
    var accumlated_time: f32 = 0;
    const time_step: f32 = 0.0167;
    main_loop: while (true) {
        accumlated_time += getDeltaTime(io);
        if (accumlated_time < time_step) continue;
        accumlated_time -= time_step;
        while (try window.poll(platform)) |event| {
            system_table.systemContextUpdate(&system_context, &.{ .delta_time = time_step, .elapsed_time = elapsed_time, .world = &world }, &event);
            switch (event) {
                .close => break :main_loop,
                .resize => |size| {
                    std.log.info("resize: {d}x{d}", .{ size.width, size.height });
                    try system_context.renderer.resize(gpa, window);
                },
                .key => |key| {
                    if (key.state == .released and key.sym == .escape) break :main_loop;
                },
                else => {},
            }
        }
        system_table.systemContextUpdate(&system_context, &.{ .delta_time = time_step, .elapsed_time = elapsed_time, .world = &world }, null);

        if (try watcher.reload(io)) {
            std.log.err("system table updated", .{});
            system_table.systemContextDeinit(&system_context);
            watcher.old_dynlib.?.close();
            watcher.old_dynlib = null;
            system_table = try .load(&watcher.dynlib.?);
            asset_server.deinit();
            asset_server = try shared.AssetServer.init(gpa, init.io);
            system_table.systemContextInit(&system_context, &system.Context.Data{
                .io = io,
                .gpa = gpa,
                .asset_server = &asset_server,
                .platform = platform,
                .window = window,
                .stream = stream,
                .server_address = addr,
            });
        }

        elapsed_time += time_step;
    }

    //TODO: Intial connect: move out.
    const disconnect_command: shared.net.Command = .disconnect;
    fixed_writer.end = 0;
    try disconnect_command.write(writer);
    std.log.debug("buffer: {any}", .{writer.buffered()});
    try stream.socket.send(io, &system_context.network_manager.server_address, writer.buffered());

    system_table.systemContextDeinit(&system_context);
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
