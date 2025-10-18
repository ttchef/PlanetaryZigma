const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const nz = @import("numz");
const physics = @import("physics.zig");
const ecs = @import("ecs");
const Renderer = @import("render/Renderer.zig");
const Spacetime = @import("net/Spacetime.zig");

pub const World = ecs.World(&.{ physics.Rigidbody, nz.Transform3D(f32) });

const width: u32 = 900;
const heigth: u32 = 800;

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
        .size = .{ .width = width, .height = heigth },
    });
    defer window.deinit();

    const renderer: Renderer = try .init(.{ .instance = .{
        .extensions = &.{
            "VK_KHR_surface",
            switch (builtin.target.os.tag) {
                .windows => "VK_KHR_win32_surface",
                .linux, .freebsd, .openbsd, .dragonfly => "VK_KHR_wayland_surface",
                .macos => "VK_MVK_macos_surface",
                else => @compileError("Unsupported OS"),
            },
            Renderer.vk.c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
        },
        .layers = &.{"VK_LAYER_KHRONOS_validation"},
    }, .device = .{
        .extensions = &.{"VK_KHR_swapchain"},
    }, .surface = .{
        .data = window,
        .init = initVulkanSurface,
    }, .swapchain = .{
        .width = width,
        .heigth = heigth,
    } });
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
        break;
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
pub extern fn glfwCreateWindowSurface(instance: *Renderer.vk.Instance, user_data: *anyopaque, allocator: ?*const anyopaque, surface: *?*Renderer.vk.Surface) c_int;

pub fn initVulkanSurface(instance: *Renderer.vk.Instance, window: *anyopaque) !*anyopaque {
    var surface: ?*Renderer.vk.Surface = null;
    _ = glfwCreateWindowSurface(@ptrCast(instance), @ptrCast(window), null, &surface);
    return surface orelse return error.VulkanCreateSurface;
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
