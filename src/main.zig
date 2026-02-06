const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("sdl");
const nz = @import("numz");
const Renderer = @import("Renderer");
const Watcher = @import("fileWatcher/watcher.zig");
const System = @import("System");
const ecs = @import("ecs");
const World = ecs.World;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var system_watcher: Watcher.Game = try .init("libsystem{s}", io);
    defer system_watcher.deinit();

    // var buffer: [4096 * 100]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    // const allocator = fba.allocator();
    // var gpa: std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }) = .init;
    var gpa: std.heap.DebugAllocator(.{ .verbose_log = false, .safety = true }) = .init;
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    try sdlCheck(sdl.SDL_Init(sdl.SDL_INIT_VIDEO));
    defer sdl.SDL_Quit();
    const window = sdl.SDL_CreateWindow("PlanetaryZigma", 600, 600, sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE) orelse return error.SdlCreateWindow;
    defer sdl.SDL_DestroyWindow(window);

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
                .severities = if (init.environ_map.contains("RENDERDOC_CAPFILE")) .{} else .{
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

    var world: World = try .init(allocator, null);
    defer world.deinit();

    var systems: System = undefined;
    const systemsInit = try system_watcher.lookup(System.InitSystems, "initSystems");
    var systemsUpdate = try system_watcher.lookup(System.UpdateSystems, "update");
    const systemsDeinit = try system_watcher.lookup(System.DeinitSystems, "deinit");
    var systemsReload = try system_watcher.lookup(System.ReloadSystems, "reload");
    if (systemsInit(&systems, &allocator, &world, &renderer_config) != 0) return error.SystemsInit;
    defer systemsDeinit(&systems, &allocator);

    var time: f64 = 0;
    var timer = try std.time.Timer.start();
    var accumulated_time: f64 = 0;
    const seconds_per_update = 0.016;

    var event: sdl.SDL_Event = undefined;
    main_loop: while (true) {
        while (sdl.SDL_PollEvent(&event)) switch (event.type) {
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => break :main_loop,
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                try systems.renderer.reCreateSwapchain(@intCast(event.window.data1), @intCast(event.window.data2));
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
            systemsUpdate(&systems, &world, seconds_per_update);
            // try Renderer.c.toErr(rendererDraw(&renderer, &world, @floatCast(time)));
            accumulated_time -= seconds_per_update;
            // if (time >= 2 * seconds_per_update)
            //     @panic("LOLXD");
        }

        if (try system_watcher.listen()) {
            systemsReload(&systems, &allocator, &world, &renderer_config, true);
            try system_watcher.reload();
            systemsReload = try system_watcher.lookup(System.ReloadSystems, "reload");
            systemsReload(&systems, &allocator, &world, &renderer_config, false);
            systemsUpdate = try system_watcher.lookup(System.UpdateSystems, "update");
        }
    }
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
