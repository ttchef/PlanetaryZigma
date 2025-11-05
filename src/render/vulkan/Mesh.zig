const std = @import("std");
const c = @import("vulkan");
const vma = @import("vma");
const nz = @import("numz");
const Device = @import("device.zig").Logical;
const Buffer = @import("Buffer.zig");

index_buffer: Buffer,
vertex_buffer: Buffer,
vertex_buffer_address: c.VkDeviceAddress,
indecies_count: u32,

pub const Vertex = extern struct {
    position: nz.Vec4(f32),
    // uv: nz.Vec2(f32) = @splat(0),
    // normal: nz.Vec3(f32) = @splat(0),
};

pub const GPUDrawPushConstants = extern struct {
    world_matrix: [16]f32,
    vertex_buffer: c.VkDeviceAddress,
};

pub fn init(device: Device, vma_allocator: vma.VmaAllocator, indices: []u32, vertices: []Vertex) !@This() {
    const vertex_buffer_size: usize = vertices.len * @sizeOf(Vertex);
    const index_buffer_size: usize = indices.len * @sizeOf(u32);

    var vertex_buffer_address: c.VkDeviceAddress = undefined;
    const vertex_buffer: Buffer = try .init(
        vma_allocator,
        vertex_buffer_size,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vma.VMA_MEMORY_USAGE_GPU_ONLY,
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
        vma.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    var staging: Buffer = try .init(
        vma_allocator,
        vertex_buffer_size + index_buffer_size,
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        vma.VMA_MEMORY_USAGE_CPU_ONLY,
    );

    var info: vma.VmaAllocationInfo = undefined;
    vma.vmaGetAllocationInfo(vma_allocator, staging.vma_allocation, &info);
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
        .indecies_count = @intCast(indices.len),
    };
}

pub fn deinit(self: @This(), vma_allocator: vma.VmaAllocator) void {
    self.index_buffer.deinit(vma_allocator);
    self.vertex_buffer.deinit(vma_allocator);
}
