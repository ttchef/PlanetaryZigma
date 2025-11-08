const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("glfw");
const nz = @import("numz");
const physics = @import("physics.zig");
const ecs = @import("ecs");
const Renderer = @import("Renderer");
const Spacetime = @import("net/Spacetime.zig");

pub const World = ecs.World(&.{ physics.Rigidbody, nz.Transform3D(f32) });

pub fn main() !void {
    // var buffer: [4096 * 100]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fba.allocator();

    var gpa: std.heap.GeneralPurposeAllocator(.{ .verbose_log = true, .safety = true }) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var world: World = try .init(allocator, null);
    defer world.deinit();

    var spacetime: Spacetime = try .init(allocator);
    defer spacetime.deinit(allocator);

    const e = world.add() catch return;
    e.set(nz.Transform3D(f32), .{}, world);

    // {
    //     var envs = std.process.EnvMap.init(allocator);
    //     defer envs.deinit();
    //     if (envs.get("ENABLE_VULKAN_RENDERDOC_CAPTURE") == null) glfw.c.glfwInitHint(glfw.c.GLFW_PLATFORM, glfw.c.GLFW_PLATFORM_X11);
    // } TODO: Use this above somehow instead of forceing X11
    glfw.c.glfwInitHint(glfw.c.GLFW_PLATFORM, glfw.c.GLFW_PLATFORM_X11);

    try glfw.init();
    defer glfw.deinit();
    glfw.Window.Hint.set(.{
        .client_api = .none,
    });
    glfw.Window.Hint.set(.{ .resizable = true });
    const window: *glfw.Window = try .init(.{
        .title = "Hello, world!",
        .size = .{ .width = 900, .height = 800 },
    });
    defer window.deinit();

    var renderer: Renderer = try .init(.{
        .instance = .{
            .extensions = blk: {
                var arr: [8][*:0]const u8 = undefined;
                arr[0] = "VK_KHR_surface";
                arr[1] = "VK_EXT_debug_utils";

                var count: usize = 2;
                var glfw_ext_count: u32 = 0;
                const glfw_exts = glfw.c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);

                if (glfw_ext_count != 0) {
                    for (glfw_exts[0..glfw_ext_count]) |ext| {
                        arr[count] = @ptrCast(ext);
                        count += 1;
                    }
                }
                break :blk arr[0..count];
            },
            .layers = &.{
                "VK_LAYER_KHRONOS_validation",
                // "VK_LAYER_LUNARG_api_dump",
            },
            .debug_config = .{
                .severities = .{
                    .warning = true,
                    .verbose = true,
                    .@"error" = true,
                    .info = true,
                },
            },
        },
        .device = .{
            .extensions = &.{
                "VK_KHR_dynamic_rendering",
                "VK_KHR_swapchain",
                "VK_EXT_descriptor_buffer",
                "VK_KHR_buffer_device_address",
            },
        },
        .surface = .{
            .data = window,
            .init = initVulkanSurface,
        },
        .swapchain = .{
            .width = @intCast(window.getSize().width),
            .heigth = @intCast(window.getSize().height),
        },
    });
    defer renderer.deinit(allocator);

    std.debug.print("About to upload mesh\n", .{});
    try renderer.uploadMeshToGPU(allocator, "assets/objects/cube.obj");
    std.debug.print("Mesh upload completed, meshes.len: {d}\n", .{renderer.meshes.items.len});

    var time: f32 = 0;
    var timer = try std.time.Timer.start();
    // var accumulated_time: f32 = 0;
    // const seconds_per_update = 0.016;

    std.debug.print("About to call renderer.draw({d})\n", .{time});
    try renderer.draw(time);
    std.debug.print("Successfully returned from renderer.draw()\n", .{});

    while (!window.shouldClose()) {
        const delta_time = @as(f32, @floatFromInt(timer.lap())) / (1000 * 1000 * 1000);
        time += delta_time;
        // accumulated_time += delta_time;

        // if (accumulated_time >= seconds_per_update) {
        try renderer.draw(time);
        if (renderer.resize_request == true) {
            const size = glfw.Window.getSize(window);
            try renderer.reCreateSwapchain(size.width, size.height);
            renderer.resize_request = false;
        }
        //     accumulated_time -= seconds_per_update;
        // }
        //     try proccessEvents(&spacetime, &world);

        //     Render.update(window, delta_time);
        //     Render.draw(pipeline, window, &world);
        //     // std.debug.print("\n======NEW LOOP======\n", .{});
        //     // var query = try world.allocQuery(&.{physics.Rigidbody}, allocator);
        //     // defer query.deinit(allocator);

        //     // for (query.items) |entity| {
        //     //     std.debug.print("enitity {d}\n", .{@intFromEnum(entity)});
        //     //     // std.debug.print("x pos {d}\n", .{entity.get(nz.Transform3D(f32), world).?.position[0]});
        //     // }
        // break;
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
pub extern fn glfwCreateWindowSurface(instance: Renderer.vk.c.VkInstance, user_data: *anyopaque, allocator: ?*const anyopaque, surface: *?*Renderer.vk.Surface) c_int;

pub fn initVulkanSurface(instance: Renderer.vk.Instance, window: *anyopaque) !*anyopaque {
    var surface: ?*Renderer.vk.Surface = null;
    _ = glfwCreateWindowSurface(instance.handle, @ptrCast(window), null, &surface);
    return surface orelse return error.VulkanCreateSurface;
}

// pub fn getDeltaTime() !f32 {
//     const Static = struct {
//         var previous: ?std.time.Instant = null;
//     };

//     const now = try std.time.Instant.now();
//     const prev = Static.previous orelse {
//         Static.previous = now;
//         return 0.0;
//     };

//     const dt_ns = now.since(prev);
//     Static.previous = now;

//     return @as(f32, @floatFromInt(dt_ns)) / 1_000_000_000.0;
// }
