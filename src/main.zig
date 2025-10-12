const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const nz = @import("numz");
const physics = @import("physics.zig");
const Ecs = @import("ecs.zig");
const Render = @import("render.zig");

pub const db = struct {
    pub const Connection = opaque {
        pub fn connect() !*@This() {
            return c.connect_to_db_ffi() orelse error.Connect;
        }
        pub fn disconnect(self: *@This()) void {
            c.free_db_connection(self);
        }
        pub fn subscribe_to_tables(self: *@This()) void {
            c.db_subscribe_to_tables(self);
        }
        pub fn run_threaded(self: *@This()) void {
            c.db_run_threaded(self);
        }
    };

    pub const c = struct {
        pub extern fn register_player_connect_callback(connection: ?*Connection, callback: ?*const fn () callconv(.c) void) void;
        pub extern fn connect_to_db_ffi() callconv(.c) ?*Connection;
        pub extern fn free_db_connection(connection: ?*Connection) callconv(.c) void;
        pub extern fn db_subscribe_to_tables(connection: ?*Connection) callconv(.c) void;
        pub extern fn db_run_threaded(connection: ?*Connection) callconv(.c) void;
    };
};

pub fn player_connect() callconv(.c) void {
    std.debug.print("Player connect\n", .{});
}

pub const World = Ecs.World(&.{ physics.Rigidbody, nz.Transform3D(f32) });

pub fn main() !void {
    var buffer: [4096 * 4 + 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const connection: *db.Connection = try .connect();
    defer connection.disconnect();

    db.c.register_player_connect_callback(connection, player_connect);
    connection.subscribe_to_tables();

    connection.run_threaded();

    var world: World = try .init(allocator, null);
    defer world.deinit();
    const e = try world.add();
    e.set(nz.Transform3D(f32), .{}, world);

    while (true) {
        // std.debug.print("\n======NEW LOOP======\n", .{});
        var query = try world.allocQuery(&.{nz.Transform3D(f32)}, allocator);
        defer query.deinit(allocator);

        for (query.items) |entity| {
            _ = entity;
            // std.debug.print("x pos {d}\n", .{entity.get(nz.Transform3D(f32), world).?.position[0]});
        }
    }

    // const window = Render.init();
    // defer Render.deinit(window);

    // const pipeline = Render.initPipeline();
    // defer Render.deinitPipeline(pipeline);

    // var time: f32 = 0;
    // while (!window.shouldClose()) {
    //     const delta_time = try getDeltaTime();
    //     time += delta_time;
    //     Render.update(window, delta_time);
    //     Render.draw(pipeline, window);
    // }
}

pub fn getDeltaTime() !f32 {
    const Static = struct {
        var previous: ?std.time.Instant = null;
    };

    const now = try std.time.Instant.now();
    const prev = Static.previous orelse {
        Static.previous = now;
        return 0.0;
    };

    const dt_ns = now.since(prev);
    Static.previous = now;

    return @as(f32, @floatFromInt(dt_ns)) / 1_000_000_000.0;
}
