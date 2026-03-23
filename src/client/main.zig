const std = @import("std");
const builtin = @import("builtin");
const shared = @import("shared");
const system = @import("system");
const World = system.World;
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = false }) = .init;
    // var gpa: std.heap.GeneralPurposeAllocator(.{ .safety = false }) = .init;
    defer _ = gpa.deinit();
    const allocator = if (builtin.mode == .Debug) gpa.allocator() else init.gpa;
    const io = init.io;

    var platform_impl = switch (builtin.os.tag) {
        .windows => try yes.Platform.Win32.get(allocator),
        .macos => @compileError("lorenzo fix this idk, figure it out"),
        else => try yes.Platform.Xlib.init(),
    };
    const platform = platform_impl.platform();

    var window_impl: @TypeOf(platform_impl).Window = .{};
    const window = &window_impl.interface;
    try window.open(platform, .{
        .title = "PlanetaryZigma",
        .size = .{ .width = 670, .height = 400 },
        .surface_type = .vulkan,
    });
    defer window.close(platform);
    try window.setCursor(platform, .crosshair);

    var asset_server = try shared.AssetServer.init(allocator, init.io);
    defer asset_server.deinit();

    var world: World = try .init(allocator);
    defer world.deinit();
    var camera = try world.ec.addEntity();
    camera.set(system.Camera, .{}, world.ec);

    var watcher: shared.Watcher = try .init("system", io);
    defer watcher.deinit(io);
    try watcher.load(io);

    var system_context: system.Context = undefined;
    var system_table: system.ffi.Table = try .load(&watcher.dynlib.?);

    system_table.systemContextInit(&system_context, &system.Context.Data{
        .allocator = allocator,
        .asset_server = &asset_server,
        .platform = platform,
        .window = window,
    });

    var elapsed_time: f32 = 0;
    // const step_time: f32 = 0.0167;
    main_loop: while (true) {
        const delta_time = getDeltaTime(io);
        while (try window.poll(platform)) |event| {
            switch (event) {
                .close => break :main_loop,
                .resize => |size| {
                    std.log.info("resize: {d}x{d}", .{ size.width, size.height });
                    try system_context.renderer.resize(allocator, window);
                },
                .key => |key| {
                    if (key.state == .released and key.sym == .escape) break :main_loop;
                },
                else => {},
            }
            system_table.systemContextUpdate(&system_context, &.{ .delta_time = delta_time, .elapsed_time = elapsed_time, .world = &world }, &event);
        }
        system_table.systemContextUpdate(&system_context, &.{ .delta_time = delta_time, .elapsed_time = elapsed_time, .world = &world }, null);

        if (try watcher.reload(io)) {
            std.log.debug("system table updated", .{});
            system_table.systemContextDeinit(&system_context);
            watcher.old_dynlib.?.close();
            system_table = try .load(&watcher.dynlib.?);
            asset_server.deinit();
            asset_server = try shared.AssetServer.init(allocator, init.io);
            system_table.systemContextInit(&system_context, &system.Context.Data{
                .allocator = allocator,
                .asset_server = &asset_server,
                .platform = platform,
                .window = window,
            });
        }
        elapsed_time += delta_time;
    }
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
