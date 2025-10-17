const std = @import("std");
const glfw = @import("glfw");
const gl = @import("gl");
const nz = @import("numz");
const physics = @import("physics.zig");
const ecs = @import("ecs");
const Render = @import("render.zig");
const Spacetime = @import("net/Spacetime.zig");
const vk = @import("render/vulkan.zig");

pub const World = ecs.World(&.{ physics.Rigidbody, nz.Transform3D(f32) });

pub fn main() !void {
    var buffer: [4096 * 100]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();
    var world: World = try .init(allocator, null);
    defer world.deinit();

    var spacetime: Spacetime = try .init(allocator);
    defer spacetime.deinit();

    const e = world.add() catch return;
    e.set(nz.Transform3D(f32), .{}, world);

    const window = Render.init();
    defer Render.deinit(window);

    const pipeline = Render.initPipeline();
    defer Render.deinitPipeline(pipeline);

    var instance: vk.c.VkInstance = undefined;
    try vk.check(vk.c.vkCreateInstance(&vk.c.VkInstanceCreateInfo{
        .sType = vk.c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &vk.c.VkApplicationInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .apiVersion = vk.c.VK_API_VERSION_1_3,
        },
    }, null, &instance));

    const vkCreateInstance = try vk.Func.Proc(.createInstance).load(instance);

    var instance2: vk.c.VkInstance = undefined;
    try vk.check(vkCreateInstance(&vk.c.VkInstanceCreateInfo{
        .sType = vk.c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &vk.c.VkApplicationInfo{
            .sType = vk.c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .apiVersion = vk.c.VK_API_VERSION_1_3,
        },
    }, null, &instance2));

    std.Thread.sleep(3000);

    while (!window.shouldClose()) {
        var time: f32 = 0;
        try proccessEvents(&spacetime, &world);

        const delta_time = try getDeltaTime();
        time += delta_time;
        Render.update(window, delta_time);
        Render.draw(pipeline, window, &world);
        // std.debug.print("\n======NEW LOOP======\n", .{});
        // var query = try world.allocQuery(&.{physics.Rigidbody}, allocator);
        // defer query.deinit(allocator);

        // for (query.items) |entity| {
        //     std.debug.print("enitity {d}\n", .{@intFromEnum(entity)});
        //     // std.debug.print("x pos {d}\n", .{entity.get(nz.Transform3D(f32), world).?.position[0]});
        // }
    }
}

pub fn proccessEvents(spacetime: *Spacetime, world: *World) !void {
    spacetime.events.lock.lock();
    defer spacetime.events.lock.unlock();
    while (spacetime.events.queue.popFront()) |event| {
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
