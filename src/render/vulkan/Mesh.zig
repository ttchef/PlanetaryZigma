const std = @import("std");
const c = @import("vulkan");
const nz = @import("numz");
const Device = @import("device.zig").Logical;
const Buffer = @import("Buffer.zig");
const Material = @import("Material.zig");
const Vma = @import("Vma.zig");

surfaces: std.ArrayList(GeoSurface),
index_buffer: Buffer,
vertex_buffer: Buffer,
vertex_buffer_address: c.VkDeviceAddress,
name: []const u8 = "default",

pub const Vertex = extern struct {
    position: [3]f32 = @splat(0),
    uv_x: f32 = 0,
    normal: [3]f32 = @splat(0),
    uv_y: f32 = 0,
    color: [4]f32 = @splat(0),
};

pub const GPUDrawPushConstants = extern struct {
    world_matrix: [16]f32,
    vertex_buffer: c.VkDeviceAddress,
};

pub const GeoSurface = struct {
    index_start: i32,
    index_count: i32,
    material: *Material.Instance,
};

pub fn init(device: Device, geo_surfaces: std.ArrayListUnmanaged(GeoSurface), vma_allocator: Vma.Allocator, indices: []u32, vertices: []Vertex) !@This() {
    const vertex_buffer_size: usize = vertices.len * @sizeOf(Vertex);
    const index_buffer_size: usize = indices.len * @sizeOf(u32);

    var vertex_buffer_address: c.VkDeviceAddress = undefined;
    const vertex_buffer: Buffer = try .init(
        vma_allocator,
        vertex_buffer_size,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        Vma.c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    var device_adress_info: c.VkBufferDeviceAddressInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = vertex_buffer.buffer,
    };
    vertex_buffer_address = c.vkGetBufferDeviceAddress(device.handle, &device_adress_info);

    const index_buffer: Buffer = try .init(
        vma_allocator,
        index_buffer_size,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        Vma.c.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    var staging: Buffer = try .init(
        vma_allocator,
        vertex_buffer_size + index_buffer_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        Vma.c.VMA_MEMORY_USAGE_CPU_ONLY,
    );

    var info: Vma.AllocationInfo = undefined;
    Vma.c.vmaGetAllocationInfo(vma_allocator, staging.vma_allocation, &info);
    const data: [*]u8 = @ptrCast(info.pMappedData);

    // copy vertex buffer
    @memcpy(data[0..vertex_buffer_size], std.mem.sliceAsBytes(vertices));
    // copy index buffer
    @memcpy(data[vertex_buffer_size .. vertex_buffer_size + index_buffer_size], std.mem.sliceAsBytes(indices));

    const cmd = try device.beginImmediateCommand();

    var vert_copy: c.VkBufferCopy = .{
        .dstOffset = 0,
        .srcOffset = 0,
        .size = vertex_buffer_size,
    };

    c.vkCmdCopyBuffer(cmd, staging.buffer, vertex_buffer.buffer, 1, &vert_copy);

    var index_copy: c.VkBufferCopy = .{
        .dstOffset = 0,
        .srcOffset = vertex_buffer_size,
        .size = index_buffer_size,
    };
    c.vkCmdCopyBuffer(cmd, staging.buffer, index_buffer.buffer, 1, &index_copy);

    try device.endImmediateCommand(cmd);

    staging.deinit(vma_allocator);

    return .{
        .index_buffer = index_buffer,
        .vertex_buffer = vertex_buffer,
        .vertex_buffer_address = vertex_buffer_address,
        .surfaces = geo_surfaces,
    };
}

pub fn deinit(self: @This(), vma_allocator: Vma.Allocator) void {
    self.index_buffer.deinit(vma_allocator);
    self.vertex_buffer.deinit(vma_allocator);
}
