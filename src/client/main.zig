const std = @import("std");
const glfw = @import("glfw");
const objc = @import("objc");
const shared = @import("shared");
const Renderer = @import("rendering/Renderer.zig");
const MetalRenderer = @import("rendering/MetalRenderer.zig");

const NSUInteger = c_ulong;

const Vertex = extern struct {
    position: [4]f32,
    color: [4]f32,
    uv: [4]f32,
};

pub fn main(init: std.process.Init) !void {
    if (glfw.glfwInit() != glfw.GLFW_TRUE) return error.GlfwInitFailed;
    defer glfw.glfwTerminate();

    glfw.glfwWindowHint(glfw.GLFW_NO_API, glfw.GLFW_TRUE);

    const window: *glfw.GLFWwindow = glfw.glfwCreateWindow(900, 800, "PlanetaryZigma", null, null) orelse return error.CreateWindow;
    defer glfw.glfwDestroyWindow(window);

    const allocator = std.heap.c_allocator;
    var asset_server = try shared.AssetServer.init(allocator, init.io);
    defer asset_server.deinit();

    const vertex_glsl = try asset_server.loadAssetNullTerminated(init.io, "shaders/colored_triangle.vert");
    defer allocator.free(vertex_glsl);
    const fragment_glsl = try asset_server.loadAssetNullTerminated(init.io, "shaders/colored_triangle.frag");
    defer allocator.free(fragment_glsl);
    const texture_image = try loadTextureRgba8(allocator, &asset_server, init.io, "textures/tile.png");
    defer allocator.free(texture_image.pixels);

    var metal_renderer = try MetalRenderer.init(allocator, window);
    const renderer = metal_renderer.renderer();
    defer renderer.deinit();

    const vertex_shader = try renderer.createShader(.{
        .stage = .vertex,
        .entry_point = "main",
        .glsl_source = vertex_glsl,
    });
    defer renderer.destroyShader(vertex_shader) catch {};

    const fragment_shader = try renderer.createShader(.{
        .stage = .fragment,
        .entry_point = "main",
        .glsl_source = fragment_glsl,
    });
    defer renderer.destroyShader(fragment_shader) catch {};

    const pipeline = try renderer.createPipeline(.{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .color_format = .bgra8_unorm,
        .topology = .triangle,
    });
    defer renderer.destroyPipeline(pipeline) catch {};

    const vertices = [_]Vertex{
        .{
            .position = .{ -0.7, 0.7, 0.0, 1.0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 1.0, 0.0, 0.0 },
        },
        .{
            .position = .{ -0.7, -0.7, 0.0, 1.0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 0.0, 0.0, 0.0, 0.0 },
        },
        .{
            .position = .{ 0.7, -0.7, 0.0, 1.0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 1.0, 0.0, 0.0, 0.0 },
        },
        .{
            .position = .{ 0.7, 0.7, 0.0, 1.0 },
            .color = .{ 1.0, 1.0, 1.0, 1.0 },
            .uv = .{ 1.0, 1.0, 0.0, 0.0 },
        },
    };
    const indices = [_]u16{ 0, 1, 2, 2, 3, 0 };

    const vertex_buffer = try renderer.createBuffer(.{
        .size = @sizeOf(@TypeOf(vertices)),
        .usage = .{ .vertex = true, .copy_dst = true },
    });
    defer renderer.destroyBuffer(vertex_buffer) catch {};
    try renderer.updateBuffer(vertex_buffer, 0, std.mem.sliceAsBytes(vertices[0..]));

    const index_buffer = try renderer.createBuffer(.{
        .size = @sizeOf(@TypeOf(indices)),
        .usage = .{ .index = true, .copy_dst = true },
    });
    defer renderer.destroyBuffer(index_buffer) catch {};
    try renderer.updateBuffer(index_buffer, 0, std.mem.sliceAsBytes(indices[0..]));

    const texture = try renderer.createTexture(.{
        .width = texture_image.width,
        .height = texture_image.height,
        .format = .rgba8_unorm,
        .usage = .{ .sampled = true, .copy_dst = true },
    });
    defer renderer.destroyTexture(texture) catch {};
    try renderer.updateTexture(texture, .{
        .width = texture_image.width,
        .height = texture_image.height,
        .bytes_per_row = texture_image.bytes_per_row,
    }, texture_image.pixels);

    const sampler = try renderer.createSampler(.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .address_mode_u = .repeat,
        .address_mode_v = .repeat,
    });
    defer renderer.destroySampler(sampler) catch {};

    while (glfw.glfwWindowShouldClose(window) != glfw.GLFW_TRUE) {
        glfw.glfwPollEvents();

        var framebuffer_width: c_int = 0;
        var framebuffer_height: c_int = 0;
        glfw.glfwGetFramebufferSize(window, &framebuffer_width, &framebuffer_height);
        if (framebuffer_width <= 0 or framebuffer_height <= 0) continue;

        renderer.beginFrame(.{
            .width = @as(u32, @intCast(framebuffer_width)),
            .height = @as(u32, @intCast(framebuffer_height)),
        }) catch |err| switch (err) {
            error.NoDrawable => continue,
            else => return err,
        };
        errdefer renderer.endFrame() catch {};

        try renderer.beginPass(.{
            .clear_color = Renderer.ClearColor{},
        });
        try renderer.setPipeline(pipeline);
        try renderer.setVertexBuffer(0, vertex_buffer, 0);
        try renderer.setIndexBuffer(index_buffer, .uint16, 0);
        try renderer.bindTexture(.fragment, 0, texture);
        try renderer.bindSampler(.fragment, 0, sampler);
        try renderer.drawIndexed(6, 0, 0);
        try renderer.endPass();
        try renderer.endFrame();
        try renderer.present();
    }
}

const TextureImage = struct {
    pixels: []u8,
    width: u32,
    height: u32,
    bytes_per_row: usize,
};

fn loadTextureRgba8(
    allocator: std.mem.Allocator,
    asset_server: *shared.AssetServer,
    io: std.Io,
    relative_path: []const u8,
) !TextureImage {
    const file_bytes = try asset_server.loadAsset(io, relative_path);
    defer allocator.free(file_bytes);

    const NSData = objc.getClass("NSData") orelse return error.NoNSData;
    const image_data = NSData.msgSend(objc.Object, "dataWithBytes:length:", .{
        file_bytes.ptr,
        @as(NSUInteger, @intCast(file_bytes.len)),
    });
    if (image_data.value == null) return error.NSDataCreateFailed;

    const NSBitmapImageRep = objc.getClass("NSBitmapImageRep") orelse return error.NoNSBitmapImageRep;
    const bitmap = NSBitmapImageRep.msgSend(objc.Object, "imageRepWithData:", .{image_data});
    if (bitmap.value == null) return error.ImageDecodeFailed;

    const width: usize = @intCast(bitmap.msgSend(NSUInteger, "pixelsWide", .{}));
    const height: usize = @intCast(bitmap.msgSend(NSUInteger, "pixelsHigh", .{}));
    if (width == 0 or height == 0) return error.InvalidImageDimensions;

    const bits_per_pixel: usize = @intCast(bitmap.msgSend(NSUInteger, "bitsPerPixel", .{}));
    const samples_per_pixel: usize = @intCast(bitmap.msgSend(NSUInteger, "samplesPerPixel", .{}));
    const bytes_per_pixel = bits_per_pixel / 8;
    if (bytes_per_pixel != 3 and bytes_per_pixel != 4) return error.UnsupportedPixelFormat;
    if (samples_per_pixel < 3) return error.UnsupportedPixelFormat;

    const src_bytes_per_row: usize = @intCast(bitmap.msgSend(NSUInteger, "bytesPerRow", .{}));
    if (src_bytes_per_row < width * bytes_per_pixel) return error.UnsupportedPixelFormat;

    const bitmap_data = bitmap.msgSend([*c]u8, "bitmapData", .{});
    if (bitmap_data == null) return error.ImageDecodeFailed;

    const bytes_per_row = width * 4;
    const total_bytes = bytes_per_row * height;
    const pixels = try allocator.alloc(u8, total_bytes);
    errdefer allocator.free(pixels);
    const src = @as([*]const u8, @ptrCast(bitmap_data));

    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const src_offset = y * src_bytes_per_row + x * bytes_per_pixel;
            const dst_offset = y * bytes_per_row + x * 4;

            pixels[dst_offset + 0] = src[src_offset + 0];
            pixels[dst_offset + 1] = src[src_offset + 1];
            pixels[dst_offset + 2] = src[src_offset + 2];
            pixels[dst_offset + 3] = if (bytes_per_pixel == 4) src[src_offset + 3] else 255;
        }
    }

    return .{
        .pixels = pixels,
        .width = @intCast(width),
        .height = @intCast(height),
        .bytes_per_row = bytes_per_row,
    };
}
