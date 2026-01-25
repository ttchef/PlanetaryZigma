const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const nz = @import("numz");
const physics = @import("physics.zig");
const Renderer = @import("Renderer");
const Watcher = @import("fileWatcher/watcher.zig");
const System = @import("System");
const WorldModule = @import("World");
const World = WorldModule.World;

pub fn main() !void {
    var watcher: Watcher.Game = try .init("librenderer{s}");
    defer watcher.deinit();
    var system_watcher: Watcher.Game = try .init("libsystem{s}");
    defer system_watcher.deinit();
    var rendererInit = try watcher.lookup(Renderer.c.Init, "init");
    var rendererDraw = try watcher.lookup(Renderer.c.Draw, "draw");
    var systemUpdate = try system_watcher.lookup(System.Update, "update");

    // var buffer: [4096 * 100]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fba.allocator();
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = false, .safety = true }) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try sdlCheck(sdl.SDL_Init(sdl.SDL_INIT_VIDEO));
    defer sdl.SDL_Quit();
    const window = sdl.SDL_CreateWindow("PlanetaryZigma", 600, 600, sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE) orelse return error.SdlCreateWindow;
    defer sdl.SDL_DestroyWindow(window);

    var world: World = try .init(allocator, null);
    defer world.deinit();

    var renderer_config: Renderer.Config = .{
        .instance = .{
            .extensions = blk: {
                var arr: [8][*:0]const u8 = undefined;
                arr[0] = "VK_EXT_debug_utils";
                var count: usize = 1;

                var sdl_ext_count: u32 = 0;
                const sdl_exts = sdl.SDL_Vulkan_GetInstanceExtensions(&sdl_ext_count);

                if (sdl_ext_count != 0) {
                    for (sdl_exts[0..sdl_ext_count]) |ext| {
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
            .width = 600,
            .heigth = 600,
        },
    };

    var renderer: Renderer = undefined;
    try Renderer.c.toErr(rendererInit(&renderer, &allocator, &renderer_config));

    try System.init(allocator, &world, &renderer);
    System.deinit();

    var time: f64 = 0;
    var timer = try std.time.Timer.start();
    var accumulated_time: f64 = 0;
    const seconds_per_update = 0.016;

    var event: sdl.SDL_Event = undefined;
    main_loop: while (true) {
        while (sdl.SDL_PollEvent(&event)) switch (event.type) {
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => break :main_loop,
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                try renderer.reCreateSwapchain(@intCast(event.window.data1), @intCast(event.window.data2));
            },
            sdl.SDL_EVENT_KEY_DOWN => {
                if (event.key.key == sdl.SDLK_ESCAPE) break :main_loop;
            },
            else => {},
        };

        const delta_time = @as(f64, @floatFromInt(timer.lap())) / (1000 * 1000 * 1000);
        time += delta_time;
        accumulated_time += delta_time;

        if (accumulated_time >= seconds_per_update) {
            systemUpdate(&world, seconds_per_update);
            try Renderer.c.toErr(rendererDraw(&renderer, &world, @floatCast(time)));
            accumulated_time -= seconds_per_update;
            // if (time >= 2 * seconds_per_update)
            //     @panic("LOLXD");
        }

        if (try watcher.listen()) {
            renderer.deinit(allocator);
            try watcher.reload();
            rendererInit = try watcher.lookup(Renderer.c.Init, "init");
            try Renderer.c.toErr(rendererInit(&renderer, &allocator, &renderer_config));
            rendererDraw = try watcher.lookup(Renderer.c.Draw, "draw");
        }
        if (try system_watcher.listen()) {
            try system_watcher.reload();
            systemUpdate = try system_watcher.lookup(System.Update, "update");
        }
    }
    renderer.deinit(allocator);
}

pub fn initVulkanSurface(instance: Renderer.vk.Instance, window: *anyopaque) anyerror!*anyopaque {
    var surface: Renderer.vk.c.VkSurfaceKHR = null;
    _ = try sdlCheck(sdl.SDL_Vulkan_CreateSurface(@ptrCast(window), @ptrCast(instance.handle), null, @ptrCast(&surface)));
    return surface orelse return error.VulkanCreateSurface;
}

pub fn sdlCheck(result: bool) !void {
    if (result) return;
    const err_message = sdl.SDL_GetError();
    std.log.scoped(.sdl).err("{s}", .{err_message});
    return error.Sdl;
}
