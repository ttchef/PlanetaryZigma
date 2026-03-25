const std = @import("std");
const glfw = @import("glfw");
const objc = @import("objc");
const shaderc = @cImport({
    @cInclude("shaderc/shaderc.h");
});
const spvc = @cImport({
    @cInclude("spirv_cross/spirv_cross_c.h");
});

const MetalRenderer = @This();

extern fn glfwGetCocoaWindow(window: *glfw.GLFWwindow) ?*anyopaque;
extern fn MTLCreateSystemDefaultDevice() ?*anyopaque;

pub const BufferHandle = enum(u32) { invalid = 0, _ };
pub const TextureHandle = enum(u32) { invalid = 0, _ };
pub const SamplerHandle = enum(u32) { invalid = 0, _ };
pub const ShaderHandle = enum(u32) { invalid = 0, _ };
pub const PipelineHandle = enum(u32) { invalid = 0, _ };

pub const Viewport = struct {
    width: u32,
    height: u32,
};

pub const ClearColor = struct {
    r: f64 = 0.08,
    g: f64 = 0.10,
    b: f64 = 0.14,
    a: f64 = 1.0,
};

pub const PixelFormat = enum {
    bgra8_unorm,
    rgba8_unorm,
    depth32_float,
};

pub const PrimitiveTopology = enum {
    triangle,
    line,
    point,
};

pub const IndexType = enum {
    uint16,
    uint32,
};

pub const ShaderStage = enum {
    vertex,
    fragment,
    compute,
};

pub const BufferUsage = packed struct(u32) {
    vertex: bool = false,
    index: bool = false,
    uniform: bool = false,
    storage: bool = false,
    copy_src: bool = false,
    copy_dst: bool = false,
    _padding: u26 = 0,
};

pub const TextureUsage = packed struct(u32) {
    sampled: bool = false,
    storage: bool = false,
    render_target: bool = false,
    copy_src: bool = false,
    copy_dst: bool = false,
    _padding: u27 = 0,
};

pub const SamplerFilter = enum {
    nearest,
    linear,
};

pub const AddressMode = enum {
    clamp_to_edge,
    repeat,
};

pub const BufferDesc = struct {
    size: usize,
    usage: BufferUsage,
};

pub const TextureDesc = struct {
    width: u32,
    height: u32,
    format: PixelFormat,
    usage: TextureUsage,
    mip_levels: u32 = 1,
};

pub const SamplerDesc = struct {
    min_filter: SamplerFilter = .linear,
    mag_filter: SamplerFilter = .linear,
    address_mode_u: AddressMode = .repeat,
    address_mode_v: AddressMode = .repeat,
};

pub const ShaderDesc = struct {
    stage: ShaderStage,
    entry_point: [:0]const u8,
    glsl_source: [:0]const u8,
};

pub const PipelineDesc = struct {
    vertex_shader: ShaderHandle,
    fragment_shader: ?ShaderHandle = null,
    color_format: PixelFormat = .bgra8_unorm,
    topology: PrimitiveTopology = .triangle,
};

pub const PassDesc = struct {
    clear_color: ?ClearColor = null,
};

pub const TextureCopy = struct {
    x: u32 = 0,
    y: u32 = 0,
    width: u32,
    height: u32,
    mip_level: u32 = 0,
    bytes_per_row: usize,
};

const NSUInteger = c_ulong;
const MTLPixelFormat = NSUInteger;

const CGSize = extern struct {
    width: f64,
    height: f64,
};
const MTLOrigin = extern struct {
    x: NSUInteger,
    y: NSUInteger,
    z: NSUInteger,
};
const MTLSize = extern struct {
    width: NSUInteger,
    height: NSUInteger,
    depth: NSUInteger,
};
const MTLRegion = extern struct {
    origin: MTLOrigin,
    size: MTLSize,
};
const MTLClearColor = extern struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

const MTLPrimitiveTypePoint: NSUInteger = 0;
const MTLPrimitiveTypeLine: NSUInteger = 1;
const MTLPrimitiveTypeTriangle: NSUInteger = 3;

const MTLIndexTypeUInt16: NSUInteger = 0;
const MTLIndexTypeUInt32: NSUInteger = 1;

const MTLLoadActionLoad: NSUInteger = 0;
const MTLLoadActionClear: NSUInteger = 2;
const MTLStoreActionStore: NSUInteger = 1;

const MTLResourceStorageModeShared: NSUInteger = 0;
const MTLTextureType2D: NSUInteger = 2;
const MTLTextureUsageShaderRead: NSUInteger = 1 << 0;
const MTLTextureUsageShaderWrite: NSUInteger = 1 << 1;
const MTLTextureUsageRenderTarget: NSUInteger = 1 << 2;

const MTLSamplerMinMagFilterNearest: NSUInteger = 0;
const MTLSamplerMinMagFilterLinear: NSUInteger = 1;
const MTLSamplerAddressModeClampToEdge: NSUInteger = 0;
const MTLSamplerAddressModeRepeat: NSUInteger = 2;

const PushConstantsSlot: NSUInteger = 30;
const MaxPushConstantsBytes: usize = 4096;

const BufferResource = struct {
    object: objc.Object,
    size: usize,
};

const TextureResource = struct {
    object: objc.Object,
    desc: TextureDesc,
};

const SamplerResource = struct {
    object: objc.Object,
};

const ShaderResource = struct {
    stage: ShaderStage,
    library: objc.Object,
    function: objc.Object,
    msl_source: [:0]u8,
};

const CompiledMsl = struct {
    source: [:0]u8,
    entry_point: [:0]u8,
};

const PipelineResource = struct {
    object: objc.Object,
    topology: PrimitiveTopology,
};

allocator: std.mem.Allocator,
window: *glfw.GLFWwindow,
device: objc.Object,
command_queue: objc.Object,
metal_layer: objc.Object,
clear_color: ClearColor = .{},

buffers: std.ArrayListUnmanaged(?BufferResource) = .{},
textures: std.ArrayListUnmanaged(?TextureResource) = .{},
samplers: std.ArrayListUnmanaged(?SamplerResource) = .{},
shaders: std.ArrayListUnmanaged(?ShaderResource) = .{},
pipelines: std.ArrayListUnmanaged(?PipelineResource) = .{},

command_buffer: ?objc.Object = null,
drawable: ?objc.Object = null,
encoder: ?objc.Object = null,
active_topology: PrimitiveTopology = .triangle,

index_buffer: ?objc.Object = null,
index_type: IndexType = .uint16,
index_offset: NSUInteger = 0,

pub fn init(allocator: std.mem.Allocator, window: *glfw.GLFWwindow) !MetalRenderer {
    const cocoa_window = glfwGetCocoaWindow(window) orelse return error.NoCocoaWindow;
    const ns_window = objc.Object.fromId(cocoa_window);
    const content_view = ns_window.msgSend(objc.Object, "contentView", .{});

    const device = objc.Object.fromId(MTLCreateSystemDefaultDevice() orelse return error.NoMetalDevice);
    const command_queue = device.msgSend(objc.Object, "newCommandQueue", .{});
    if (command_queue.value == null) return error.NoMetalCommandQueue;

    const CAMetalLayer = objc.getClass("CAMetalLayer") orelse return error.NoCAMetalLayer;
    const metal_layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});
    metal_layer.msgSend(void, "setDevice:", .{device});
    metal_layer.msgSend(void, "setPixelFormat:", .{toMTLPixelFormat(.bgra8_unorm)});
    metal_layer.msgSend(void, "setFramebufferOnly:", .{objcBool(true)});

    content_view.msgSend(void, "setWantsLayer:", .{objcBool(true)});
    content_view.msgSend(void, "setLayer:", .{metal_layer});

    return .{
        .allocator = allocator,
        .window = window,
        .device = device,
        .command_queue = command_queue,
        .metal_layer = metal_layer,
    };
}

// pub fn renderer(self: *MetalRenderer) {
//     return .{
//         .ptr = self,
//         .vtable = &vtable,
//     };
// }

pub fn deinit(self: *MetalRenderer) void {
    _ = self.endPass() catch {};
    if (self.command_buffer != null) {
        _ = self.present() catch {};
    }

    for (self.pipelines.items) |entry| {
        if (entry) |pipeline| pipeline.object.msgSend(void, "release", .{});
    }
    for (self.shaders.items) |entry| {
        if (entry) |shader| {
            shader.function.msgSend(void, "release", .{});
            shader.library.msgSend(void, "release", .{});
            self.allocator.free(shader.msl_source);
        }
    }
    for (self.samplers.items) |entry| {
        if (entry) |sampler| sampler.object.msgSend(void, "release", .{});
    }
    for (self.textures.items) |entry| {
        if (entry) |texture| texture.object.msgSend(void, "release", .{});
    }
    for (self.buffers.items) |entry| {
        if (entry) |buffer| buffer.object.msgSend(void, "release", .{});
    }

    self.pipelines.deinit(self.allocator);
    self.shaders.deinit(self.allocator);
    self.samplers.deinit(self.allocator);
    self.textures.deinit(self.allocator);
    self.buffers.deinit(self.allocator);

    self.command_queue.msgSend(void, "release", .{});
    self.device.msgSend(void, "release", .{});
}

// pub fn backend(_: *MetalRenderer) Backend {
//     return .metal;
// }

pub fn beginFrame(self: *MetalRenderer, viewport: Viewport) !void {
    if (self.command_buffer != null) return error.FrameAlreadyBegun;

    self.metal_layer.msgSend(void, "setDrawableSize:", .{CGSize{
        .width = @floatFromInt(viewport.width),
        .height = @floatFromInt(viewport.height),
    }});

    const drawable = self.metal_layer.msgSend(objc.Object, "nextDrawable", .{});
    if (drawable.value == null) return error.NoDrawable;
    self.drawable = drawable;

    const command_buffer = self.command_queue.msgSend(objc.Object, "commandBuffer", .{});
    if (command_buffer.value == null) return error.NoCommandBuffer;
    self.command_buffer = command_buffer;
}

pub fn endFrame(self: *MetalRenderer) !void {
    try self.endPass();
}

pub fn present(self: *MetalRenderer) !void {
    if (self.encoder != null) try self.endPass();

    const drawable = self.drawable orelse return error.NoDrawable;
    const command_buffer = self.command_buffer orelse return error.FrameNotBegun;

    command_buffer.msgSend(void, "presentDrawable:", .{drawable});
    command_buffer.msgSend(void, "commit", .{});

    self.drawable = null;
    self.command_buffer = null;
    self.index_buffer = null;
    self.index_offset = 0;
}

pub fn createBuffer(self: *MetalRenderer, desc: BufferDesc) !BufferHandle {
    const buffer = self.device.msgSend(objc.Object, "newBufferWithLength:options:", .{
        @as(NSUInteger, @intCast(desc.size)),
        MTLResourceStorageModeShared,
    });
    if (buffer.value == null) return error.BufferCreateFailed;

    return try appendHandle(
        BufferHandle,
        BufferResource,
        self.allocator,
        &self.buffers,
        .{ .object = buffer, .size = desc.size },
    );
}

pub fn createTexture(self: *MetalRenderer, desc: TextureDesc) !TextureHandle {
    const MTLTextureDescriptor = objc.getClass("MTLTextureDescriptor") orelse return error.NoMTLTextureDescriptor;
    const texture_descriptor = MTLTextureDescriptor.msgSend(objc.Object, "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", .{
        toMTLPixelFormat(desc.format),
        @as(NSUInteger, desc.width),
        @as(NSUInteger, desc.height),
        objcBool(desc.mip_levels > 1),
    });
    if (texture_descriptor.value == null) return error.TextureDescriptorCreateFailed;

    texture_descriptor.msgSend(void, "setTextureType:", .{MTLTextureType2D});
    texture_descriptor.msgSend(void, "setUsage:", .{toMTLTextureUsage(desc.usage)});

    const texture = self.device.msgSend(objc.Object, "newTextureWithDescriptor:", .{texture_descriptor});
    if (texture.value == null) return error.TextureCreateFailed;

    return try appendHandle(
        TextureHandle,
        TextureResource,
        self.allocator,
        &self.textures,
        .{ .object = texture, .desc = desc },
    );
}

pub fn createSampler(self: *MetalRenderer, desc: SamplerDesc) !SamplerHandle {
    const MTLSamplerDescriptor = objc.getClass("MTLSamplerDescriptor") orelse return error.NoMTLSamplerDescriptor;
    const sampler_descriptor = MTLSamplerDescriptor.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    defer sampler_descriptor.msgSend(void, "release", .{});

    sampler_descriptor.msgSend(void, "setMinFilter:", .{toMTLFilter(desc.min_filter)});
    sampler_descriptor.msgSend(void, "setMagFilter:", .{toMTLFilter(desc.mag_filter)});
    sampler_descriptor.msgSend(void, "setSAddressMode:", .{toMTLAddressMode(desc.address_mode_u)});
    sampler_descriptor.msgSend(void, "setTAddressMode:", .{toMTLAddressMode(desc.address_mode_v)});

    const sampler = self.device.msgSend(objc.Object, "newSamplerStateWithDescriptor:", .{sampler_descriptor});
    if (sampler.value == null) return error.SamplerCreateFailed;

    return try appendHandle(
        SamplerHandle,
        SamplerResource,
        self.allocator,
        &self.samplers,
        .{ .object = sampler },
    );
}

pub fn createShader(self: *MetalRenderer, desc: ShaderDesc) !ShaderHandle {
    const compiled_msl = try compileGlslToMsl(self.allocator, desc.glsl_source, desc.stage, desc.entry_point);
    errdefer self.allocator.free(compiled_msl.source);
    errdefer self.allocator.free(compiled_msl.entry_point);

    const NSString = objc.getClass("NSString") orelse return error.NoNSString;
    const MTLCompileOptions = objc.getClass("MTLCompileOptions") orelse return error.NoMTLCompileOptions;

    const source_nsstring = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{compiled_msl.source.ptr});
    const entry_nsstring = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{compiled_msl.entry_point.ptr});

    const compile_options = MTLCompileOptions.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    defer compile_options.msgSend(void, "release", .{});

    var library_error: ?objc.c.id = null;
    const library = self.device.msgSend(objc.Object, "newLibraryWithSource:options:error:", .{
        source_nsstring,
        compile_options,
        &library_error,
    });
    if (library.value == null) {
        logNSError(library_error);
        return error.ShaderCompileFailed;
    }

    const function = library.msgSend(objc.Object, "newFunctionWithName:", .{entry_nsstring});
    if (function.value == null) {
        library.msgSend(void, "release", .{});
        self.allocator.free(compiled_msl.entry_point);
        return error.ShaderEntryPointMissing;
    }

    self.allocator.free(compiled_msl.entry_point);

    return try appendHandle(
        ShaderHandle,
        ShaderResource,
        self.allocator,
        &self.shaders,
        .{
            .stage = desc.stage,
            .library = library,
            .function = function,
            .msl_source = compiled_msl.source,
        },
    );
}

pub fn createPipeline(self: *MetalRenderer, desc: PipelineDesc) !PipelineHandle {
    const vertex_shader = try lookup(
        ShaderHandle,
        ShaderResource,
        &self.shaders,
        desc.vertex_shader,
    );
    if (vertex_shader.stage != .vertex) return error.InvalidVertexShader;

    const fragment_shader = if (desc.fragment_shader) |fragment_handle| blk: {
        const shader = try lookup(
            ShaderHandle,
            ShaderResource,
            &self.shaders,
            fragment_handle,
        );
        if (shader.stage != .fragment) return error.InvalidFragmentShader;
        break :blk shader;
    } else null;

    const MTLRenderPipelineDescriptor = objc.getClass("MTLRenderPipelineDescriptor") orelse return error.NoPipelineDescriptor;
    const pipeline_descriptor = MTLRenderPipelineDescriptor.msgSend(objc.Object, "alloc", .{}).msgSend(objc.Object, "init", .{});
    defer pipeline_descriptor.msgSend(void, "release", .{});

    pipeline_descriptor.msgSend(void, "setVertexFunction:", .{vertex_shader.function});
    if (fragment_shader) |shader| {
        pipeline_descriptor.msgSend(void, "setFragmentFunction:", .{shader.function});
    }

    const color_attachments = pipeline_descriptor.msgSend(objc.Object, "colorAttachments", .{});
    const attachment_0 = color_attachments.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(NSUInteger, 0)});
    attachment_0.msgSend(void, "setPixelFormat:", .{toMTLPixelFormat(desc.color_format)});

    var pipeline_error: ?objc.c.id = null;
    const pipeline = self.device.msgSend(objc.Object, "newRenderPipelineStateWithDescriptor:error:", .{
        pipeline_descriptor,
        &pipeline_error,
    });
    if (pipeline.value == null) {
        logNSError(pipeline_error);
        return error.PipelineCreateFailed;
    }

    return try appendHandle(
        PipelineHandle,
        PipelineResource,
        self.allocator,
        &self.pipelines,
        .{
            .object = pipeline,
            .topology = desc.topology,
        },
    );
}

pub fn destroyBuffer(self: *MetalRenderer, handle: BufferHandle) !void {
    const entry = try lookupPtr(
        BufferHandle,
        BufferResource,
        &self.buffers,
        handle,
    );
    const resource = entry.*.?;
    resource.object.msgSend(void, "release", .{});
    entry.* = null;
}

pub fn destroyTexture(self: *MetalRenderer, handle: TextureHandle) !void {
    const entry = try lookupPtr(
        TextureHandle,
        TextureResource,
        &self.textures,
        handle,
    );
    const resource = entry.*.?;
    resource.object.msgSend(void, "release", .{});
    entry.* = null;
}

pub fn destroySampler(self: *MetalRenderer, handle: SamplerHandle) !void {
    const entry = try lookupPtr(
        SamplerHandle,
        SamplerResource,
        &self.samplers,
        handle,
    );
    const resource = entry.*.?;
    resource.object.msgSend(void, "release", .{});
    entry.* = null;
}

pub fn destroyShader(self: *MetalRenderer, handle: ShaderHandle) !void {
    const entry = try lookupPtr(
        ShaderHandle,
        ShaderResource,
        &self.shaders,
        handle,
    );
    const resource = entry.*.?;
    resource.function.msgSend(void, "release", .{});
    resource.library.msgSend(void, "release", .{});
    self.allocator.free(resource.msl_source);
    entry.* = null;
}

pub fn destroyPipeline(self: *MetalRenderer, handle: PipelineHandle) !void {
    const entry = try lookupPtr(
        PipelineHandle,
        PipelineResource,
        &self.pipelines,
        handle,
    );
    const resource = entry.*.?;
    resource.object.msgSend(void, "release", .{});
    entry.* = null;
}

pub fn updateBuffer(self: *MetalRenderer, handle: BufferHandle, offset: usize, data: []const u8) !void {
    const buffer = try lookup(
        BufferHandle,
        BufferResource,
        &self.buffers,
        handle,
    );
    if (offset + data.len > buffer.size) return error.BufferWriteOutOfBounds;
    if (data.len == 0) return;

    const raw_ptr = buffer.object.msgSend([*]u8, "contents", .{});
    const dst = raw_ptr[offset .. offset + data.len];
    @memcpy(dst, data);
}

pub fn updateTexture(self: *MetalRenderer, handle: TextureHandle, copy: TextureCopy, data: []const u8) !void {
    const texture = try lookup(
        TextureHandle,
        TextureResource,
        &self.textures,
        handle,
    );

    const min_bytes = copy.bytes_per_row * copy.height;
    if (data.len < min_bytes) return error.TextureUploadTooSmall;

    const max_x = copy.x + copy.width;
    const max_y = copy.y + copy.height;
    if (max_x > texture.desc.width or max_y > texture.desc.height) return error.TextureWriteOutOfBounds;

    const region = MTLRegion{
        .origin = .{
            .x = copy.x,
            .y = copy.y,
            .z = 0,
        },
        .size = .{
            .width = copy.width,
            .height = copy.height,
            .depth = 1,
        },
    };

    texture.object.msgSend(void, "replaceRegion:mipmapLevel:withBytes:bytesPerRow:", .{
        region,
        @as(NSUInteger, copy.mip_level),
        data.ptr,
        @as(NSUInteger, @intCast(copy.bytes_per_row)),
    });
}

pub fn beginPass(self: *MetalRenderer, desc: PassDesc) !void {
    if (self.command_buffer == null) return error.FrameNotBegun;
    if (self.encoder != null) return error.PassAlreadyBegun;

    const drawable = self.drawable orelse return error.NoDrawable;
    const command_buffer = self.command_buffer.?;

    const texture = drawable.msgSend(objc.Object, "texture", .{});
    const MTLRenderPassDescriptor = objc.getClass("MTLRenderPassDescriptor") orelse return error.NoRenderPassDescriptor;
    const pass_descriptor = MTLRenderPassDescriptor.msgSend(objc.Object, "renderPassDescriptor", .{});

    const color_attachments = pass_descriptor.msgSend(objc.Object, "colorAttachments", .{});
    const attachment_0 = color_attachments.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(NSUInteger, 0)});
    attachment_0.msgSend(void, "setTexture:", .{texture});
    attachment_0.msgSend(void, "setStoreAction:", .{MTLStoreActionStore});

    if (desc.clear_color) |clear| {
        attachment_0.msgSend(void, "setLoadAction:", .{MTLLoadActionClear});
        attachment_0.msgSend(void, "setClearColor:", .{MTLClearColor{
            .red = clear.r,
            .green = clear.g,
            .blue = clear.b,
            .alpha = clear.a,
        }});
    } else {
        attachment_0.msgSend(void, "setLoadAction:", .{MTLLoadActionLoad});
    }

    const encoder = command_buffer.msgSend(objc.Object, "renderCommandEncoderWithDescriptor:", .{pass_descriptor});
    if (encoder.value == null) return error.EncoderCreateFailed;
    self.encoder = encoder;
}

pub fn endPass(self: *MetalRenderer) !void {
    if (self.encoder) |encoder| {
        encoder.msgSend(void, "endEncoding", .{});
        self.encoder = null;
        self.index_buffer = null;
        self.index_offset = 0;
    }
}

pub fn setPipeline(self: *MetalRenderer, pipeline_handle: PipelineHandle) !void {
    const encoder = self.encoder orelse return error.NoActivePass;
    const pipeline = try lookup(
        PipelineHandle,
        PipelineResource,
        &self.pipelines,
        pipeline_handle,
    );
    encoder.msgSend(void, "setRenderPipelineState:", .{pipeline.object});
    self.active_topology = pipeline.topology;
}

pub fn setVertexBuffer(self: *MetalRenderer, slot: u32, buffer_handle: BufferHandle, offset: usize) !void {
    const encoder = self.encoder orelse return error.NoActivePass;
    const buffer = try lookup(
        BufferHandle,
        BufferResource,
        &self.buffers,
        buffer_handle,
    );
    encoder.msgSend(void, "setVertexBuffer:offset:atIndex:", .{
        buffer.object,
        @as(NSUInteger, @intCast(offset)),
        @as(NSUInteger, slot),
    });
}

pub fn setIndexBuffer(self: *MetalRenderer, buffer_handle: BufferHandle, index_type: IndexType, offset: usize) !void {
    const buffer = try lookup(
        BufferHandle,
        BufferResource,
        &self.buffers,
        buffer_handle,
    );
    self.index_buffer = buffer.object;
    self.index_type = index_type;
    self.index_offset = @as(NSUInteger, @intCast(offset));
}

pub fn bindTexture(self: *MetalRenderer, stage: ShaderStage, slot: u32, texture_handle: TextureHandle) !void {
    const encoder = self.encoder orelse return error.NoActivePass;
    const texture = try lookup(
        TextureHandle,
        TextureResource,
        &self.textures,
        texture_handle,
    );
    switch (stage) {
        .vertex => encoder.msgSend(void, "setVertexTexture:atIndex:", .{
            texture.object,
            @as(NSUInteger, slot),
        }),
        .fragment => encoder.msgSend(void, "setFragmentTexture:atIndex:", .{
            texture.object,
            @as(NSUInteger, slot),
        }),
        .compute => return error.UnsupportedFeature,
    }
}

pub fn bindSampler(self: *MetalRenderer, stage: ShaderStage, slot: u32, sampler_handle: SamplerHandle) !void {
    const encoder = self.encoder orelse return error.NoActivePass;
    const sampler = try lookup(
        SamplerHandle,
        SamplerResource,
        &self.samplers,
        sampler_handle,
    );
    switch (stage) {
        .vertex => encoder.msgSend(void, "setVertexSamplerState:atIndex:", .{
            sampler.object,
            @as(NSUInteger, slot),
        }),
        .fragment => encoder.msgSend(void, "setFragmentSamplerState:atIndex:", .{
            sampler.object,
            @as(NSUInteger, slot),
        }),
        .compute => return error.UnsupportedFeature,
    }
}

pub fn pushConstants(self: *MetalRenderer, stage: ShaderStage, data: []const u8) !void {
    const encoder = self.encoder orelse return error.NoActivePass;
    if (data.len > MaxPushConstantsBytes) return error.PushConstantsTooLarge;

    const length: NSUInteger = @intCast(data.len);
    const index = PushConstantsSlot;
    switch (stage) {
        .vertex => encoder.msgSend(void, "setVertexBytes:length:atIndex:", .{ data.ptr, length, index }),
        .fragment => encoder.msgSend(void, "setFragmentBytes:length:atIndex:", .{ data.ptr, length, index }),
        .compute => return error.UnsupportedFeature,
    }
}

pub fn draw(self: *MetalRenderer, vertex_count: u32, first_vertex: u32) !void {
    const encoder = self.encoder orelse return error.NoActivePass;
    encoder.msgSend(void, "drawPrimitives:vertexStart:vertexCount:", .{
        toMTLPrimitiveType(self.active_topology),
        @as(NSUInteger, first_vertex),
        @as(NSUInteger, vertex_count),
    });
}

pub fn drawIndexed(self: *MetalRenderer, index_count: u32, first_index: u32, base_vertex: i32) !void {
    _ = base_vertex;
    const encoder = self.encoder orelse return error.NoActivePass;
    const index_buffer = self.index_buffer orelse return error.NoIndexBuffer;

    const index_stride: NSUInteger = switch (self.index_type) {
        .uint16 => 2,
        .uint32 => 4,
    };
    const index_offset = self.index_offset + @as(NSUInteger, first_index) * index_stride;

    encoder.msgSend(void, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:", .{
        toMTLPrimitiveType(self.active_topology),
        @as(NSUInteger, index_count),
        toMTLIndexType(self.index_type),
        index_buffer,
        index_offset,
    });
}

pub fn dispatch(_: *MetalRenderer, _: u32, _: u32, _: u32) !void {
    return error.UnsupportedFeature;
}

fn compileGlslToMsl(
    allocator: std.mem.Allocator,
    glsl_source: [:0]const u8,
    stage: ShaderStage,
    entry_point: [:0]const u8,
) !CompiledMsl {
    const shader_kind: shaderc.shaderc_shader_kind = switch (stage) {
        .vertex => shaderc.shaderc_vertex_shader,
        .fragment => shaderc.shaderc_fragment_shader,
        .compute => shaderc.shaderc_compute_shader,
    };

    const compiler = shaderc.shaderc_compiler_initialize() orelse return error.ShadercCompilerInitFailed;
    defer shaderc.shaderc_compiler_release(compiler);

    const options = shaderc.shaderc_compile_options_initialize() orelse return error.ShadercOptionsInitFailed;
    defer shaderc.shaderc_compile_options_release(options);

    shaderc.shaderc_compile_options_set_source_language(options, shaderc.shaderc_source_language_glsl);
    shaderc.shaderc_compile_options_set_target_env(
        options,
        shaderc.shaderc_target_env_vulkan,
        shaderc.shaderc_env_version_vulkan_1_2,
    );

    const result = shaderc.shaderc_compile_into_spv(
        compiler,
        glsl_source.ptr,
        glsl_source.len,
        shader_kind,
        "runtime_shader.glsl",
        entry_point.ptr,
        options,
    ) orelse return error.ShadercCompileFailed;
    defer shaderc.shaderc_result_release(result);

    if (shaderc.shaderc_result_get_compilation_status(result) != shaderc.shaderc_compilation_status_success) {
        const err_ptr = shaderc.shaderc_result_get_error_message(result);
        if (err_ptr != null) {
            std.log.err("shaderc compile error: {s}", .{std.mem.sliceTo(err_ptr, 0)});
        }
        return error.ShadercCompileFailed;
    }

    const spirv_len_bytes = shaderc.shaderc_result_get_length(result);
    if (spirv_len_bytes == 0 or spirv_len_bytes % @sizeOf(u32) != 0) return error.InvalidSpirvOutput;

    const spirv_word_count = spirv_len_bytes / @sizeOf(u32);
    const spirv_words = try allocator.alloc(u32, spirv_word_count);
    defer allocator.free(spirv_words);

    const spirv_bytes_ptr = shaderc.shaderc_result_get_bytes(result) orelse return error.InvalidSpirvOutput;
    const spirv_bytes = @as([*]const u8, @ptrCast(spirv_bytes_ptr))[0..spirv_len_bytes];
    @memcpy(std.mem.sliceAsBytes(spirv_words), spirv_bytes);

    var context: spvc.spvc_context = undefined;
    try spvcCheck(
        spvc.spvc_context_create(&context),
        null,
        "spvc_context_create failed",
    );
    defer spvc.spvc_context_destroy(context);

    var parsed_ir: spvc.spvc_parsed_ir = undefined;
    try spvcCheck(
        spvc.spvc_context_parse_spirv(context, @ptrCast(spirv_words.ptr), spirv_words.len, &parsed_ir),
        context,
        "spvc_context_parse_spirv failed",
    );

    var msl_compiler: spvc.spvc_compiler = undefined;
    try spvcCheck(
        spvc.spvc_context_create_compiler(
            context,
            spvc.SPVC_BACKEND_MSL,
            parsed_ir,
            spvc.SPVC_CAPTURE_MODE_TAKE_OWNERSHIP,
            &msl_compiler,
        ),
        context,
        "spvc_context_create_compiler failed",
    );

    var entry_points: [*c]const spvc.spvc_entry_point = null;
    var num_entry_points: usize = 0;
    try spvcCheck(
        spvc.spvc_compiler_get_entry_points(msl_compiler, &entry_points, &num_entry_points),
        context,
        "spvc_compiler_get_entry_points failed",
    );
    if (entry_points == null or num_entry_points == 0) return error.NoSpirvEntryPoint;

    const entry = entry_points[0];
    if (entry.name == null) return error.NoSpirvEntryPointName;
    const desired_entry_name: [*:0]const u8 = switch (stage) {
        .vertex => "vertex_main",
        .fragment => "fragment_main",
        .compute => "compute_main",
    };
    try spvcCheck(
        spvc.spvc_compiler_rename_entry_point(msl_compiler, entry.name, desired_entry_name, entry.execution_model),
        context,
        "spvc_compiler_rename_entry_point failed",
    );
    const cleansed_entry_name = spvc.spvc_compiler_get_cleansed_entry_point_name(msl_compiler, desired_entry_name, entry.execution_model) orelse return error.NoSpirvEntryPointName;

    var msl_options: spvc.spvc_compiler_options = undefined;
    try spvcCheck(
        spvc.spvc_compiler_create_compiler_options(msl_compiler, &msl_options),
        context,
        "spvc_compiler_create_compiler_options failed",
    );
    try spvcCheck(
        spvc.spvc_compiler_options_set_uint(msl_options, spvc.SPVC_COMPILER_OPTION_MSL_PLATFORM, spvc.SPVC_MSL_PLATFORM_MACOS),
        context,
        "spvc_compiler_options_set_uint(MSL_PLATFORM) failed",
    );
    try spvcCheck(
        spvc.spvc_compiler_install_compiler_options(msl_compiler, msl_options),
        context,
        "spvc_compiler_install_compiler_options failed",
    );

    var msl_source_ptr: [*c]const u8 = null;
    try spvcCheck(
        spvc.spvc_compiler_compile(msl_compiler, &msl_source_ptr),
        context,
        "spvc_compiler_compile failed",
    );
    if (msl_source_ptr == null) return error.SpirvCrossCompileFailed;

    const out_source = try allocator.dupeZ(u8, std.mem.sliceTo(msl_source_ptr, 0));
    errdefer allocator.free(out_source);
    const out_entry = try allocator.dupeZ(u8, std.mem.sliceTo(cleansed_entry_name, 0));

    return .{
        .source = out_source,
        .entry_point = out_entry,
    };
}

fn spvcCheck(result: spvc.spvc_result, context: ?spvc.spvc_context, message: []const u8) !void {
    if (result == spvc.SPVC_SUCCESS) return;
    if (context) |ctx| {
        const details = spvc.spvc_context_get_last_error_string(ctx);
        if (details != null) {
            std.log.err("{s}: {s}", .{ message, std.mem.sliceTo(details, 0) });
            return error.SpirvCrossFailed;
        }
    }
    std.log.err("{s}", .{message});
    return error.SpirvCrossFailed;
}

// const vtable: VTable = .{
//     .deinit = vtableDeinit,
//     .backend = vtableBackend,
//     .begin_frame = vtableBeginFrame,
//     .end_frame = vtableEndFrame,
//     .present = vtablePresent,
//     .create_buffer = vtableCreateBuffer,
//     .create_texture = vtableCreateTexture,
//     .create_sampler = vtableCreateSampler,
//     .create_shader = vtableCreateShader,
//     .create_pipeline = vtableCreatePipeline,
//     .destroy_buffer = vtableDestroyBuffer,
//     .destroy_texture = vtableDestroyTexture,
//     .destroy_sampler = vtableDestroySampler,
//     .destroy_shader = vtableDestroyShader,
//     .destroy_pipeline = vtableDestroyPipeline,
//     .update_buffer = vtableUpdateBuffer,
//     .update_texture = vtableUpdateTexture,
//     .begin_pass = vtableBeginPass,
//     .end_pass = vtableEndPass,
//     .set_pipeline = vtableSetPipeline,
//     .set_vertex_buffer = vtableSetVertexBuffer,
//     .set_index_buffer = vtableSetIndexBuffer,
//     .bind_texture = vtableBindTexture,
//     .bind_sampler = vtableBindSampler,
//     .push_constants = vtablePushConstants,
//     .draw = vtableDraw,
//     .draw_indexed = vtableDrawIndexed,
//     .dispatch = vtableDispatch,
// };
//
fn vtableDeinit(ptr: *anyopaque) void {
    const self: *MetalRenderer = castSelf(ptr);
    self.deinit();
}

// fn vtableBackend(ptr: *anyopaque) Backend {
//     const self: *MetalRenderer = castSelf(ptr);
//     return self.backend();
// }

fn vtableBeginFrame(ptr: *anyopaque, viewport: Viewport) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.beginFrame(viewport);
}

fn vtableEndFrame(ptr: *anyopaque) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.endFrame();
}

fn vtablePresent(ptr: *anyopaque) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.present();
}

fn vtableCreateBuffer(ptr: *anyopaque, desc: BufferDesc) anyerror!BufferHandle {
    const self: *MetalRenderer = castSelf(ptr);
    return try self.createBuffer(desc);
}

fn vtableCreateTexture(ptr: *anyopaque, desc: TextureDesc) anyerror!TextureHandle {
    const self: *MetalRenderer = castSelf(ptr);
    return try self.createTexture(desc);
}

fn vtableCreateSampler(ptr: *anyopaque, desc: SamplerDesc) anyerror!SamplerHandle {
    const self: *MetalRenderer = castSelf(ptr);
    return try self.createSampler(desc);
}

fn vtableCreateShader(ptr: *anyopaque, desc: ShaderDesc) anyerror!ShaderHandle {
    const self: *MetalRenderer = castSelf(ptr);
    return try self.createShader(desc);
}

fn vtableCreatePipeline(ptr: *anyopaque, desc: PipelineDesc) anyerror!PipelineHandle {
    const self: *MetalRenderer = castSelf(ptr);
    return try self.createPipeline(desc);
}

fn vtableDestroyBuffer(ptr: *anyopaque, handle: BufferHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.destroyBuffer(handle);
}

fn vtableDestroyTexture(ptr: *anyopaque, handle: TextureHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.destroyTexture(handle);
}

fn vtableDestroySampler(ptr: *anyopaque, handle: SamplerHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.destroySampler(handle);
}

fn vtableDestroyShader(ptr: *anyopaque, handle: ShaderHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.destroyShader(handle);
}

fn vtableDestroyPipeline(ptr: *anyopaque, handle: PipelineHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.destroyPipeline(handle);
}

fn vtableUpdateBuffer(ptr: *anyopaque, handle: BufferHandle, offset: usize, data: []const u8) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.updateBuffer(handle, offset, data);
}

fn vtableUpdateTexture(ptr: *anyopaque, handle: TextureHandle, copy: TextureCopy, data: []const u8) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.updateTexture(handle, copy, data);
}

fn vtableBeginPass(ptr: *anyopaque, desc: PassDesc) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.beginPass(desc);
}

fn vtableEndPass(ptr: *anyopaque) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.endPass();
}

fn vtableSetPipeline(ptr: *anyopaque, pipeline: PipelineHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.setPipeline(pipeline);
}

fn vtableSetVertexBuffer(ptr: *anyopaque, slot: u32, buffer: BufferHandle, offset: usize) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.setVertexBuffer(slot, buffer, offset);
}

fn vtableSetIndexBuffer(ptr: *anyopaque, buffer: BufferHandle, index_type: IndexType, offset: usize) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.setIndexBuffer(buffer, index_type, offset);
}

fn vtableBindTexture(ptr: *anyopaque, stage: ShaderStage, slot: u32, texture: TextureHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.bindTexture(stage, slot, texture);
}

fn vtableBindSampler(ptr: *anyopaque, stage: ShaderStage, slot: u32, sampler: SamplerHandle) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.bindSampler(stage, slot, sampler);
}

fn vtablePushConstants(ptr: *anyopaque, stage: ShaderStage, data: []const u8) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.pushConstants(stage, data);
}

fn vtableDraw(ptr: *anyopaque, vertex_count: u32, first_vertex: u32) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.draw(vertex_count, first_vertex);
}

fn vtableDrawIndexed(ptr: *anyopaque, index_count: u32, first_index: u32, base_vertex: i32) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.drawIndexed(index_count, first_index, base_vertex);
}

fn vtableDispatch(ptr: *anyopaque, x: u32, y: u32, z: u32) anyerror!void {
    const self: *MetalRenderer = castSelf(ptr);
    try self.dispatch(x, y, z);
}

fn castSelf(ptr: *anyopaque) *MetalRenderer {
    return @ptrCast(@alignCast(ptr));
}

fn appendHandle(
    comptime Handle: type,
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayListUnmanaged(?T),
    value: T,
) !Handle {
    try list.append(allocator, value);
    return @enumFromInt(list.items.len);
}

fn lookup(
    comptime Handle: type,
    comptime T: type,
    list: *std.ArrayListUnmanaged(?T),
    handle: Handle,
) !T {
    const index = try handleIndex(Handle, handle);
    if (index >= list.items.len) return error.InvalidHandle;
    return list.items[index] orelse return error.InvalidHandle;
}

fn lookupPtr(
    comptime Handle: type,
    comptime T: type,
    list: *std.ArrayListUnmanaged(?T),
    handle: Handle,
) !*?T {
    const index = try handleIndex(Handle, handle);
    if (index >= list.items.len) return error.InvalidHandle;
    if (list.items[index] == null) return error.InvalidHandle;
    return &list.items[index];
}

fn handleIndex(comptime Handle: type, handle: Handle) !usize {
    const raw: u32 = @intFromEnum(handle);
    if (raw == 0) return error.InvalidHandle;
    return raw - 1;
}

fn toMTLPixelFormat(format: PixelFormat) MTLPixelFormat {
    return switch (format) {
        .bgra8_unorm => 80,
        .rgba8_unorm => 70,
        .depth32_float => 252,
    };
}

fn toMTLTextureUsage(usage: TextureUsage) NSUInteger {
    var out: NSUInteger = 0;
    if (usage.sampled) out |= MTLTextureUsageShaderRead;
    if (usage.storage) out |= MTLTextureUsageShaderWrite;
    if (usage.render_target) out |= MTLTextureUsageRenderTarget;
    return out;
}

fn toMTLFilter(filter: SamplerFilter) NSUInteger {
    return switch (filter) {
        .nearest => MTLSamplerMinMagFilterNearest,
        .linear => MTLSamplerMinMagFilterLinear,
    };
}

fn toMTLAddressMode(mode: AddressMode) NSUInteger {
    return switch (mode) {
        .clamp_to_edge => MTLSamplerAddressModeClampToEdge,
        .repeat => MTLSamplerAddressModeRepeat,
    };
}

fn toMTLPrimitiveType(topology: PrimitiveTopology) NSUInteger {
    return switch (topology) {
        .triangle => MTLPrimitiveTypeTriangle,
        .line => MTLPrimitiveTypeLine,
        .point => MTLPrimitiveTypePoint,
    };
}

fn toMTLIndexType(index_type: IndexType) NSUInteger {
    return switch (index_type) {
        .uint16 => MTLIndexTypeUInt16,
        .uint32 => MTLIndexTypeUInt32,
    };
}

fn logNSError(err_ptr: ?objc.c.id) void {
    const raw_err = err_ptr orelse return;
    const err = objc.Object.fromId(raw_err);
    const description = err.msgSend(objc.Object, "localizedDescription", .{});
    const utf8 = description.msgSend([*c]const u8, "UTF8String", .{});
    if (utf8 == null) return;
    std.log.err("Objective-C error: {s}", .{std.mem.sliceTo(utf8, 0)});
}

fn objcBool(value: bool) objc.c.BOOL {
    return switch (objc.c.BOOL) {
        bool => value,
        i8 => @intFromBool(value),
        else => @compileError("unexpected Objective-C BOOL type"),
    };
}
