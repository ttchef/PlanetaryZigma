const std = @import("std");
const nz = @import("numz");

connection: c.Connection,
events: Events,

pub const c = struct {
    pub const Connection = *opaque {};

    pub const callback = struct {
        pub const PlayerConnect = *const fn (*Player, *Events) callconv(.c) void;
    };

    pub extern fn connect_to_db_ffi() callconv(.c) ?Connection;
    pub extern fn free_db_connection(connection: Connection) callconv(.c) void;

    pub extern fn register_player_connect_callback(
        connection: Connection,
        events: *Events,
        callback: callback.PlayerConnect,
    ) void;

    pub extern fn db_subscribe_to_tables(connection: Connection) callconv(.c) void;
    pub extern fn db_run_threaded(connection: Connection) callconv(.c) void;

    pub extern fn free_cplayer(p: *Player) void;
};

pub const Events = struct {
    lock: std.Thread.Mutex = .{},
    queue: std.Deque(Type) = .empty,

    pub const Type = union(enum) {
        player_connect: Player,
    };
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

pub fn init(allocator: std.mem.Allocator) !@This() {
    const connection: c.Connection = c.connect_to_db_ffi() orelse return error.Connect;

    var events: Events = .{};
    try events.queue.ensureTotalCapacity(allocator, 1024);

    c.register_player_connect_callback(connection, &events, playerConnect);
    c.db_subscribe_to_tables(connection);
    c.db_run_threaded(connection);

    return .{
        .connection = connection,
        .events = events,
    };
}

pub fn deinit(self: @This()) void {
    c.free_db_connection(self.connection);
}

// your callback that Rust will call
fn playerConnect(player: *Player, events: *Events) callconv(.c) void {
    std.debug.print("Player connected:\n", .{});
    std.debug.print("\tid: {}\n", .{player.player_id});
    std.debug.print("\tname: {s}\n", .{player.name});
    std.debug.print("\tpos: ({}, {}, {})\n", .{ player.position[0], player.position[1], player.position[2] });

    events.lock.lock();
    defer events.lock.unlock();
    events.queue.pushBackAssumeCapacity(.{ .player_connect = player.* });

    // std.debug.print("Entities {d}", .{events.signatures.items.len});
    // std.debug.print("TOT {d}:\n", .{events.?.generation.items.len});
}
