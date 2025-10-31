const std = @import("std");
const c = @import("vulkan");
const vma = @import("vma");
const nz = @import("numz");
const Device = @import("device.zig").Logical;
const Buffer = @import("Buffer.zig");

index_buffer: Buffer,
vertex_buffer: Buffer,
vertex_buffer_address: c.VkDeviceAddress,

pub const Vertex = packed struct {
    position: nz.Vec3(f32),
    uv_x: f32 = 0,
    normal: nz.Vec3(f32) = @splat(0),
    uv_y: f32 = 0,
    color: nz.Vec4(f32),
};

pub const GPUDrawPushConstants = struct {
    world_matrix: nz.Mat4x4(f32),
    vertex_buffer: c.VkDeviceAddress,
};

pub fn init(device: Device, vma_allocator: vma.VmaAllocator, indices: []i32, vertices: []Vertex) !@This() {
    const vertex_buffer_size: usize = vertices.len * @sizeOf(Vertex);
    const index_buffer_size: usize = indices.len * @sizeOf(i32);

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

    var staging: Buffer = try .init(vma_allocator, vertex_buffer_size + index_buffer_size, c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vma.VMA_MEMORY_USAGE_CPU_ONLY);

    var info: vma.VmaAllocationInfo = undefined;
    vma.vmaGetAllocationInfo(vma_allocator, staging.vma_allocation, &info);
    const data: [*]u8 = @ptrCast(@alignCast(info.pMappedData));

    // copy vertex buffer
    @memcpy(data[0..vertex_buffer_size], vertices);
    // memcpy(data, vertices.data(), vertex_buffer_size);
    // copy index buffer
    @memcpy(data[vertex_buffer_size .. vertex_buffer_size + index_buffer_size], indices);

    // memcpy((char*)data + vertex_buffer_size, indices.data(), index_buffer_size);

    const cmd = device.beginImmediateCommand();

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

    device.endImmediateCommand();

    staging.deinit(vma_allocator);

    return .{
        .index_buffer = index_buffer,
        .vertex_buffer = vert_copy,
        .vertex_buffer_address = vertex_buffer_address,
    };
}
