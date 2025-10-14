const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const nz = @import("numz");
const physics = @import("physics.zig");
const ecs = @import("ecs");
const Render = @import("render.zig");

pub const db = struct {
    pub var events: struct {
        lock: std.Thread.Mutex = .{},
        queue: std.Deque(Event) = .empty,
    } = .{};

    pub const Event = union(enum) {
        player_connect: Player,
    };

    pub const Callback = union(enum) {
        pub const PlayerConnect = *const fn (*Player, *World) callconv(.c) void;

        player_connect: PlayerConnect,
    };

    pub fn connect() !Connection {
        return c.connect_to_db_ffi() orelse error.Connect;
    }

    pub const Connection = *opaque {
        pub fn close(self: *@This()) void {
            c.free_db_connection(self);
        }

        pub fn subscribeToTables(self: *@This()) void {
            c.db_subscribe_to_tables(self);
        }

        pub fn runThreaded(self: *@This()) void {
            c.db_run_threaded(self);
        }

        pub fn setCallback(self: *@This(), callback: Callback, world: *World) void {
            switch (callback) {
                .player_connect => |player_connect| c.register_player_connect_callback(
                    self,
                    world,
                    player_connect,
                ),
            }
        }
    };

    pub const Player = extern struct {
        identity: [32]u8,
        player_id: u32,
        name: [*:0]const u8, // C string pointer
        position: nz.Vec3(f32),
        rotation: nz.Vec3(f32),
        direction: nz.Vec3(f32),

        pub fn deinit(self: @This()) void {
            c.free_cplayer(self);
        }
    };

    pub const c = struct {
        pub extern fn connect_to_db_ffi() callconv(.c) ?Connection;
        pub extern fn free_db_connection(connection: Connection) callconv(.c) void;

        pub extern fn register_player_connect_callback(
            connection: Connection,
            world: *World,
            callback: Callback.PlayerConnect,
        ) void;

        pub extern fn db_subscribe_to_tables(connection: Connection) callconv(.c) void;
        pub extern fn db_run_threaded(connection: Connection) callconv(.c) void;

        pub extern fn free_cplayer(p: *Player) void;
    };
};

// your callback that Rust will call
pub fn playerConnect(player: *db.Player, world: *World) callconv(.c) void {
    _ = world;
    std.debug.print("Player connected:\n", .{});
    std.debug.print("\tid: {}\n", .{player.player_id});
    std.debug.print("\tname: {s}\n", .{player.name});
    std.debug.print("\tpos: ({}, {}, {})\n", .{ player.position[0], player.position[1], player.position[2] });

    db.events.lock.lock();
    db.events.queue.pushBackAssumeCapacity(.{ .player_connect = player.* });
    db.events.lock.unlock();

    // std.debug.print("Entities {d}", .{world.signatures.items.len});
    // std.debug.print("TOT {d}:\n", .{world.?.generation.items.len});
}

pub const World = ecs.World(&.{ physics.Rigidbody, nz.Transform3D(f32) });

pub fn main() !void {
    var buffer: [4096 * 100]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var world: World = try .init(allocator, null);
    defer world.deinit();

    try db.events.queue.ensureTotalCapacity(allocator, 1000);

    const connection: db.Connection = try db.connect();
    defer connection.close();

    std.debug.print("In PTR: {*}\n", .{&world});

    connection.setCallback(.{ .player_connect = playerConnect }, &world);
    connection.subscribeToTables();

    connection.runThreaded();

    const e = world.add() catch return;
    e.set(nz.Transform3D(f32), .{}, world);

    std.Thread.sleep(3000);

    while (true) {
        try proccessEvents(&world);

        // std.debug.print("\n======NEW LOOP======\n", .{});
        var query = try world.allocQuery(&.{physics.Rigidbody}, allocator);
        defer query.deinit(allocator);

        for (query.items) |entity| {
            std.debug.print("enitity {d}\n", .{@intFromEnum(entity)});
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

pub fn proccessEvents(world: *World) !void {
    db.events.lock.lock();
    defer db.events.lock.unlock();
    while (db.events.queue.popFront()) |event| {
        switch (event) {
            .player_connect => |player_info| {
                const player = try world.*.add();
                player.set(nz.Transform3D(f32), .{ .position = player_info.position }, world.*);
                player.set(physics.Rigidbody, .{}, world.*);
            },
        }
    }
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
