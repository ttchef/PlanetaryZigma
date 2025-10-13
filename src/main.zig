const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const nz = @import("numz");
const physics = @import("physics.zig");
const ecs = @import("ecs");
const Render = @import("render.zig");

pub const CPlayer = extern struct {
    identity: [32]u8,
    player_id: u32,
    name: [*:0]const u8, // C string pointer
    position: nz.Vec3(f32),
    rotation: nz.Vec3(f32),
    direction: nz.Vec3(f32),
};

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
        pub extern fn register_player_connect_callback(
            connection: ?*Connection,
            game_state: ?*World,
            callback: ?*const fn (player: ?*CPlayer, world: ?*World) callconv(.c) void,
        ) void;
        extern fn free_cplayer(p: ?*CPlayer) void;
        pub extern fn connect_to_db_ffi() callconv(.c) ?*Connection;
        pub extern fn free_db_connection(connection: ?*Connection) callconv(.c) void;
        pub extern fn db_subscribe_to_tables(connection: ?*Connection) callconv(.c) void;
        pub extern fn db_run_threaded(connection: ?*Connection) callconv(.c) void;
    };
};

// your callback that Rust will call
pub fn player_connect(p: ?*CPlayer, world: ?*World) callconv(.c) void {
    std.debug.print("ZULULUL\n", .{});
    if (world != null) {
        std.debug.print("ZULULUL2\n", .{});

        const e = world.?.*.add() catch return;
        e.set(nz.Transform3D(f32), .{}, world.?.*);
    }
    std.debug.print("ZULULUL4\n", .{});

    if (p) |player| {
        const name = std.mem.span(player.name);
        std.debug.print("Player connected:\n", .{});
        std.debug.print("  id: {}\n", .{player.player_id});
        std.debug.print("  name: {s}\n", .{name});
        std.debug.print("  pos: ({}, {}, {})\n", .{ player.position[0], player.position[1], player.position[2] });
    } else {
        std.debug.print("player_connect called with null\n", .{});
    }
    // std.debug.print("TOT {d}:\n", .{world.?.generation.items.len});
}

pub const World = ecs.World(&.{ physics.Rigidbody, nz.Transform3D(f32) });

pub fn main() !void {
    var buffer: [4096 * 4 + 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var world: World = try .init(allocator, null);
    defer world.deinit();

    const connection: *db.Connection = try .connect();
    defer connection.disconnect();

    db.c.register_player_connect_callback(connection, &world, player_connect);
    connection.subscribe_to_tables();

    connection.run_threaded();

    std.Thread.sleep(3000);

    while (true) {

        // std.debug.print("\n======NEW LOOP======\n", .{});
        // var query = try world.allocQuery(&.{nz.Transform3D(f32)}, allocator);
        // defer query.deinit(allocator);

        // for (query.items) |entity| {
        //     _ = entity;
        //     // std.debug.print("x pos {d}\n", .{entity.get(nz.Transform3D(f32), world).?.position[0]});
        // }
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
