const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const World = system.World;
const Info = system.Info;

stream: std.Io.net.Stream,
server_address: std.Io.net.IpAddress,
server_listen: std.Io.Future(@typeInfo(@TypeOf(listen)).@"fn".return_type.?),
command_queue: shared.net.CommandQueue = .{},
io: std.Io = undefined,
allocator: std.mem.Allocator = undefined,
enitity_mapping: std.AutoHashMap(u32, u32) = undefined,

pub fn init(self: *@This(), allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, server_address: std.Io.net.IpAddress) !void {
    self.server_listen = try io.concurrent(listen, .{ allocator, io, stream, &self.command_queue });
    self.stream = stream;
    self.server_address = server_address;
    self.io = io;
    self.allocator = allocator;
    self.enitity_mapping = .init(allocator);
}

pub fn listen(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, command_queue: *shared.net.CommandQueue) !void {
    std.log.debug("hello 1", .{});
    var buffer: [1024]u8 = undefined;
    while (true) {
        const msg = stream.socket.receive(io, &buffer) catch |err| {
            if (err == error.WouldBlock) continue;
            return err;
        };

        var msg_reader: std.Io.Reader = .fixed(&buffer);
        const reader = &msg_reader;
        std.log.debug("data: {any}", .{msg.data});

        const parsed = try shared.net.Command.parse(reader);

        try command_queue.mutex.lock(io);
        try command_queue.commands.append(allocator, parsed.command);
        command_queue.mutex.unlock(io);
    }
}

pub fn update(self: *@This(), info: *const Info) !void {
    try self.command_queue.mutex.lock(self.io);
    for (self.command_queue.commands.items) |command| {
        // const input_command: shared.net.Command.Input
        switch (command) {
            .acknowledge => {
                var new_camera = try info.world.ec.addEntity();
                new_camera.set(system.Camera, .{ .transform = .{ .position = .{ 0, 0, 40 } } }, info.world.ec);
                try self.enitity_mapping.put(command.acknowledge.id, @intCast(@intFromEnum(new_camera)));
                std.debug.print("enetiess : {d}\n", .{info.world.ec.entity_count});
            },
            .spawn_entity => {
                _ = try info.world.ec.addEntity();
                std.debug.print("enetiess : {d}\n", .{info.world.ec.entity_count});
            },
            .update_transform => {
                const update_trensform_command = command.update_transform;
                //TODO: CHANGE TO NOT BE CAMERA BUT TRANSFORM: Lucas
                var camera = info.world.ec.entityGetPtr(system.Camera, @enumFromInt(update_trensform_command.id)).?;
                camera.transform.position = update_trensform_command.pos;
            },
            else => {
                std.log.err("Unhandled command {s}", .{@tagName(command)});
            },
        }
    }
    self.command_queue.commands.clearAndFree(self.allocator);
    self.command_queue.mutex.unlock(self.io);
}
