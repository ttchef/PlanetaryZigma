const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const nz = @import("numz");
const physics = @import("physics.zig");
const ecs = @import("ecs");
const Renderer = @import("render/Renderer.zig");
const Spacetime = @import("net/Spacetime.zig");

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

    try glfw.init();
    defer glfw.deinit();
    glfw.Window.Hint.set(.{ .client_api = .none });
    const window: *glfw.Window = try .init(.{
        .title = "Hello, world!",
        .size = .{ .width = 900, .height = 800 },
    });
    defer window.deinit();

    const renderer: Renderer = try .init(.{
        .instance = .{
            .extensions = &.{
                "VK_KHR_surface",
                switch (builtin.target.os.tag) {
                    .windows => "VK_KHR_win32_surface",
                    .linux, .freebsd, .openbsd, .dragonfly => "VK_KHR_wayland_surface",
                    .macos => "VK_MVK_macos_surface",
                    else => @compileError("Unsupported OS"),
                },
                "VK_EXT_debug_utils",
                "VK_PRESENT_MODE_MAILBOX_KHR",
            },
            .layers = &.{"VK_LAYER_KHRONOS_validation"},
        },
        .device = .{
            .extensions = &.{"VK_KHR_swapchain"},
        },
        .surface = .{
            .data = window,
            .init = initVulkanSurface,
        },
    });
    defer renderer.deinit();

    // const pipeline = Render.initPipeline();
    // defer Render.deinitPipeline(pipeline);

    std.Thread.sleep(3000);

    while (!window.shouldClose()) {
        //     var time: f32 = 0;
        //     try proccessEvents(&spacetime, &world);

        //     const delta_time = try getDeltaTime();
        //     time += delta_time;
        //     Render.update(window, delta_time);
        //     Render.draw(pipeline, window, &world);
        //     // std.debug.print("\n======NEW LOOP======\n", .{});
        //     // var query = try world.allocQuery(&.{physics.Rigidbody}, allocator);
        //     // defer query.deinit(allocator);

        //     // for (query.items) |entity| {
        //     //     std.debug.print("enitity {d}\n", .{@intFromEnum(entity)});
        //     //     // std.debug.print("x pos {d}\n", .{entity.get(nz.Transform3D(f32), world).?.position[0]});
        //     // }
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

pub fn initVulkanSurface(instance: *Renderer.vk.Instance, window: *anyopaque) !*anyopaque {
    const surface = glfw.vulkan.initSurface(@ptrCast(instance), @ptrCast(window), null);
    return surface orelse return error.SdlVulkanCreateSurface;
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
