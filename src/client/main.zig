const std = @import("std");
const glfw = @import("glfw");
const shared = @import("shared");
const Renderer = @import("Renderer.zig");

// const NSUInteger = c_ulong;
//
// const Vertex = extern struct {
//     position: [4]f32,
//     color: [4]f32,
//     uv: [4]f32,
// };

pub fn main(init: std.process.Init) !void {
    if (glfw.glfwInit() != glfw.GLFW_TRUE) return error.GlfwInitFailed;
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_NO_API, glfw.GLFW_TRUE);

    const window: *glfw.GLFWwindow = glfw.glfwCreateWindow(900, 800, "PlanetaryZigma", null, null) orelse return error.CreateWindow;
    defer glfw.glfwDestroyWindow(window);

    const allocator = std.heap.c_allocator;
    var asset_server = try shared.AssetServer.init(allocator, init.io);
    defer asset_server.deinit();

    var renderer: Renderer = try .init(allocator);
    defer renderer.deinit();

    // const vertex_glsl = try asset_server.loadAssetZ(init.io, "shaders/colored_triangle.vert");
    // defer allocator.free(vertex_glsl);
    // const fragment_glsl = try asset_server.loadAssetZ(init.io, "shaders/colored_triangle.frag");
    // defer allocator.free(fragment_glsl);
    // const texture_image = try loadTextureRgba8(allocator, &asset_server, init.io, "textures/tile.png");
    // defer allocator.free(texture_image.pixels);
    //
    // var metal_renderer = try MetalRenderer.init(allocator, window);
    // const renderer = metal_renderer.renderer();
    // defer renderer.deinit();
    //
    // const vertex_shader = try renderer.createShader(.{
    //     .stage = .vertex,
    //     .entry_point = "main",
    //     .glsl_source = vertex_glsl,
    // });
    // defer renderer.destroyShader(vertex_shader) catch {};
    //
    // const fragment_shader = try renderer.createShader(.{
    //     .stage = .fragment,
    //     .entry_point = "main",
    //     .glsl_source = fragment_glsl,
    // });
    // defer renderer.destroyShader(fragment_shader) catch {};
    //
    // const pipeline = try renderer.createPipeline(.{
    //     .vertex_shader = vertex_shader,
    //     .fragment_shader = fragment_shader,
    //     .color_format = .bgra8_unorm,
    //     .topology = .triangle,
    // });
    // defer renderer.destroyPipeline(pipeline) catch {};
    //
    // const vertices = [_]Vertex{
    //     .{
    //         .position = .{ -0.7, 0.7, 0.0, 1.0 },
    //         .color = .{ 1.0, 1.0, 1.0, 1.0 },
    //         .uv = .{ 0.0, 1.0, 0.0, 0.0 },
    //     },
    //     .{
    //         .position = .{ -0.7, -0.7, 0.0, 1.0 },
    //         .color = .{ 1.0, 1.0, 1.0, 1.0 },
    //         .uv = .{ 0.0, 0.0, 0.0, 0.0 },
    //     },
    //     .{
    //         .position = .{ 0.7, -0.7, 0.0, 1.0 },
    //         .color = .{ 1.0, 1.0, 1.0, 1.0 },
    //         .uv = .{ 1.0, 0.0, 0.0, 0.0 },
    //     },
    //     .{
    //         .position = .{ 0.7, 0.7, 0.0, 1.0 },
    //         .color = .{ 1.0, 1.0, 1.0, 1.0 },
    //         .uv = .{ 1.0, 1.0, 0.0, 0.0 },
    //     },
    // };
    // const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };
    //
    // const vertex_buffer = try renderer.createBuffer(.{
    //     .size = @sizeOf(@TypeOf(vertices)),
    //     .usage = .{ .vertex = true, .copy_dst = true },
    // });
    // defer renderer.destroyBuffer(vertex_buffer) catch {};
    // try renderer.updateBuffer(vertex_buffer, 0, std.mem.sliceAsBytes(vertices[0..]));
    //
    // const index_buffer = try renderer.createBuffer(.{
    //     .size = @sizeOf(@TypeOf(indices)),
    //     .usage = .{ .index = true, .copy_dst = true },
    // });
    // defer renderer.destroyBuffer(index_buffer) catch {};
    // try renderer.updateBuffer(index_buffer, 0, std.mem.sliceAsBytes(indices[0..]));
    //
    // const texture = try renderer.createTexture(.{
    //     .width = texture_image.width,
    //     .height = texture_image.height,
    //     .format = .rgba8_unorm,
    //     .usage = .{ .sampled = true, .copy_dst = true },
    // });
    // defer renderer.destroyTexture(texture) catch {};
    // try renderer.updateTexture(texture, .{
    //     .width = texture_image.width,
    //     .height = texture_image.height,
    //     .bytes_per_row = texture_image.bytes_per_row,
    // }, texture_image.pixels);
    //
    // const sampler = try renderer.createSampler(.{
    //     .min_filter = .linear,
    //     .mag_filter = .linear,
    //     .address_mode_u = .repeat,
    //     .address_mode_v = .repeat,
    // });
    // defer renderer.destroySampler(sampler) catch {};

    while (glfw.glfwWindowShouldClose(window) != glfw.GLFW_TRUE) {
        glfw.glfwPollEvents();
        try renderer.update();

        // var framebuffer_width: c_int = 0;
        // var framebuffer_height: c_int = 0;
        // glfw.glfwGetFramebufferSize(window, &framebuffer_width, &framebuffer_height);
        // if (framebuffer_width <= 0 or framebuffer_height <= 0) continue;
        //
        // renderer.beginFrame(.{
        //     .width = @as(u32, @intCast(framebuffer_width)),
        //     .height = @as(u32, @intCast(framebuffer_height)),
        // }) catch |err| switch (err) {
        //     error.NoDrawable => continue,
        //     else => return err,
        // };
        // errdefer renderer.endFrame() catch {};
        //
        // try renderer.beginPass(.{
        //     .clear_color = Renderer.ClearColor{},
        // });
        // try renderer.setPipeline(pipeline);
        // try renderer.setVertexBuffer(0, vertex_buffer, 0);
        // try renderer.setIndexBuffer(index_buffer, .uint16, 0);
        // try renderer.bindTexture(.fragment, 0, texture);
        // try renderer.bindSampler(.fragment, 0, sampler);
        // try renderer.drawIndexed(6, 0, 0);
        // try renderer.endPass();
        // try renderer.endFrame();
        // try renderer.present();
    }
}
