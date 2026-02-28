const Renderer = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const Backend = enum {
    metal,
    vulkan,
};

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

pub const VTable = struct {
    deinit: *const fn (ptr: *anyopaque) void,
    backend: *const fn (ptr: *anyopaque) Backend,

    begin_frame: *const fn (ptr: *anyopaque, viewport: Viewport) anyerror!void,
    end_frame: *const fn (ptr: *anyopaque) anyerror!void,
    present: *const fn (ptr: *anyopaque) anyerror!void,

    create_buffer: *const fn (ptr: *anyopaque, desc: BufferDesc) anyerror!BufferHandle,
    create_texture: *const fn (ptr: *anyopaque, desc: TextureDesc) anyerror!TextureHandle,
    create_sampler: *const fn (ptr: *anyopaque, desc: SamplerDesc) anyerror!SamplerHandle,
    create_shader: *const fn (ptr: *anyopaque, desc: ShaderDesc) anyerror!ShaderHandle,
    create_pipeline: *const fn (ptr: *anyopaque, desc: PipelineDesc) anyerror!PipelineHandle,

    destroy_buffer: *const fn (ptr: *anyopaque, handle: BufferHandle) anyerror!void,
    destroy_texture: *const fn (ptr: *anyopaque, handle: TextureHandle) anyerror!void,
    destroy_sampler: *const fn (ptr: *anyopaque, handle: SamplerHandle) anyerror!void,
    destroy_shader: *const fn (ptr: *anyopaque, handle: ShaderHandle) anyerror!void,
    destroy_pipeline: *const fn (ptr: *anyopaque, handle: PipelineHandle) anyerror!void,

    update_buffer: *const fn (ptr: *anyopaque, handle: BufferHandle, offset: usize, data: []const u8) anyerror!void,
    update_texture: *const fn (ptr: *anyopaque, handle: TextureHandle, copy: TextureCopy, data: []const u8) anyerror!void,

    begin_pass: *const fn (ptr: *anyopaque, desc: PassDesc) anyerror!void,
    end_pass: *const fn (ptr: *anyopaque) anyerror!void,

    set_pipeline: *const fn (ptr: *anyopaque, pipeline: PipelineHandle) anyerror!void,
    set_vertex_buffer: *const fn (ptr: *anyopaque, slot: u32, buffer: BufferHandle, offset: usize) anyerror!void,
    set_index_buffer: *const fn (ptr: *anyopaque, buffer: BufferHandle, index_type: IndexType, offset: usize) anyerror!void,
    bind_texture: *const fn (ptr: *anyopaque, stage: ShaderStage, slot: u32, texture: TextureHandle) anyerror!void,
    bind_sampler: *const fn (ptr: *anyopaque, stage: ShaderStage, slot: u32, sampler: SamplerHandle) anyerror!void,
    push_constants: *const fn (ptr: *anyopaque, stage: ShaderStage, data: []const u8) anyerror!void,

    draw: *const fn (ptr: *anyopaque, vertex_count: u32, first_vertex: u32) anyerror!void,
    draw_indexed: *const fn (ptr: *anyopaque, index_count: u32, first_index: u32, base_vertex: i32) anyerror!void,
    dispatch: *const fn (ptr: *anyopaque, x: u32, y: u32, z: u32) anyerror!void,
};

pub fn deinit(self: Renderer) void {
    self.vtable.deinit(self.ptr);
}

pub fn backend(self: Renderer) Backend {
    return self.vtable.backend(self.ptr);
}

pub fn beginFrame(self: Renderer, viewport: Viewport) !void {
    try self.vtable.begin_frame(self.ptr, viewport);
}

pub fn endFrame(self: Renderer) !void {
    try self.vtable.end_frame(self.ptr);
}

pub fn present(self: Renderer) !void {
    try self.vtable.present(self.ptr);
}

pub fn createBuffer(self: Renderer, desc: BufferDesc) !BufferHandle {
    return try self.vtable.create_buffer(self.ptr, desc);
}

pub fn createTexture(self: Renderer, desc: TextureDesc) !TextureHandle {
    return try self.vtable.create_texture(self.ptr, desc);
}

pub fn createSampler(self: Renderer, desc: SamplerDesc) !SamplerHandle {
    return try self.vtable.create_sampler(self.ptr, desc);
}

pub fn createShader(self: Renderer, desc: ShaderDesc) !ShaderHandle {
    return try self.vtable.create_shader(self.ptr, desc);
}

pub fn createPipeline(self: Renderer, desc: PipelineDesc) !PipelineHandle {
    return try self.vtable.create_pipeline(self.ptr, desc);
}

pub fn destroyBuffer(self: Renderer, handle: BufferHandle) !void {
    try self.vtable.destroy_buffer(self.ptr, handle);
}

pub fn destroyTexture(self: Renderer, handle: TextureHandle) !void {
    try self.vtable.destroy_texture(self.ptr, handle);
}

pub fn destroySampler(self: Renderer, handle: SamplerHandle) !void {
    try self.vtable.destroy_sampler(self.ptr, handle);
}

pub fn destroyShader(self: Renderer, handle: ShaderHandle) !void {
    try self.vtable.destroy_shader(self.ptr, handle);
}

pub fn destroyPipeline(self: Renderer, handle: PipelineHandle) !void {
    try self.vtable.destroy_pipeline(self.ptr, handle);
}

pub fn updateBuffer(self: Renderer, handle: BufferHandle, offset: usize, data: []const u8) !void {
    try self.vtable.update_buffer(self.ptr, handle, offset, data);
}

pub fn updateTexture(self: Renderer, handle: TextureHandle, copy: TextureCopy, data: []const u8) !void {
    try self.vtable.update_texture(self.ptr, handle, copy, data);
}

pub fn beginPass(self: Renderer, desc: PassDesc) !void {
    try self.vtable.begin_pass(self.ptr, desc);
}

pub fn endPass(self: Renderer) !void {
    try self.vtable.end_pass(self.ptr);
}

pub fn setPipeline(self: Renderer, pipeline: PipelineHandle) !void {
    try self.vtable.set_pipeline(self.ptr, pipeline);
}

pub fn setVertexBuffer(self: Renderer, slot: u32, buffer: BufferHandle, offset: usize) !void {
    try self.vtable.set_vertex_buffer(self.ptr, slot, buffer, offset);
}

pub fn setIndexBuffer(self: Renderer, buffer: BufferHandle, index_type: IndexType, offset: usize) !void {
    try self.vtable.set_index_buffer(self.ptr, buffer, index_type, offset);
}

pub fn bindTexture(self: Renderer, stage: ShaderStage, slot: u32, texture: TextureHandle) !void {
    try self.vtable.bind_texture(self.ptr, stage, slot, texture);
}

pub fn bindSampler(self: Renderer, stage: ShaderStage, slot: u32, sampler: SamplerHandle) !void {
    try self.vtable.bind_sampler(self.ptr, stage, slot, sampler);
}

pub fn pushConstants(self: Renderer, stage: ShaderStage, data: []const u8) !void {
    try self.vtable.push_constants(self.ptr, stage, data);
}

pub fn draw(self: Renderer, vertex_count: u32, first_vertex: u32) !void {
    try self.vtable.draw(self.ptr, vertex_count, first_vertex);
}

pub fn drawIndexed(self: Renderer, index_count: u32, first_index: u32, base_vertex: i32) !void {
    try self.vtable.draw_indexed(self.ptr, index_count, first_index, base_vertex);
}

pub fn dispatch(self: Renderer, x: u32, y: u32, z: u32) !void {
    try self.vtable.dispatch(self.ptr, x, y, z);
}
