const vma = @import("vma");
const nz = @import("numz");
const Buffer = @import("Buffer.zig");


const Vertex = packed struct {
    position: nz.Vec3(f32),
    uv_x: f32,
    normal: nz.Vec3(f32),
    uv_y: f32,
    color: nz.Vec4(f32),
};

const GPUMeshBuffers = packed struct {
    index_buffer: Buffer,
    vertex_buffer: Buffer,
    vertex_buffer_address: c.VkDeviceAddress,
};

const GPUDrawPushConstants = packed struct {
    world_matrix: nz.Vec4(f32),
    vertex_buffer: c.VkDeviceAddress,
};


pub fn init() GPUMeshBuffers {
    const vertex_buffer_size: usize = vertices.len * @sizeOf(Vertex);
    const index_buffer_size: usize = indices.len * @sizeOf(i32);

    var new_mesh: GPUMeshBuffers = undefined;
    new_mesh.vertex_buffer = Buffer.init(
        vma_allocator,
        vertex_buffer_size,
        c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        vma.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    var device_adress_info: c.VkBufferDeviceAddressInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
        .buffer = new_mesh.vertexBuffer.buffer,
    };
    new_mesh.vertexBufferAddress = c.vkGetBufferDeviceAddress(device, &device_adress_info);

    new_mesh.indexBuffer = Buffer.init(
        vma_allocator,
        index_buffer_size,
        c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        vma.VMA_MEMORY_USAGE_GPU_ONLY,
    );

    return new_mesh;
}

pub fn uploadMeshToGPU(device: c.VkDevice, vma_allocator: vma.VmaAllocator, indices: []i32, vertices: []Vertex) void {

    var staging: Buffer = .init(vertexBufferSize + indexBufferSize, VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VMA_MEMORY_USAGE_CPU_ONLY);

    var data = staging.vma_allocation.GetMappedData();

	// copy vertex buffer
    @memcpy(data, vertices);
	// memcpy(data, vertices.data(), vertexBufferSize);
	// copy index buffer
    @memcpy(data[vertices.len], indices);

	// memcpy((char*)data + vertexBufferSize, indices.data(), indexBufferSize);

	immediate_submit([&](VkCommandBuffer cmd) {
		VkBufferCopy vertexCopy{ 0 };
		vertexCopy.dstOffset = 0;
		vertexCopy.srcOffset = 0;
		vertexCopy.size = vertexBufferSize;

		vkCmdCopyBuffer(cmd, staging.buffer, newSurface.vertexBuffer.buffer, 1, &vertexCopy);

		VkBufferCopy indexCopy{ 0 };
		indexCopy.dstOffset = 0;
		indexCopy.srcOffset = vertexBufferSize;
		indexCopy.size = indexBufferSize;

		vkCmdCopyBuffer(cmd, staging.buffer, newSurface.indexBuffer.buffer, 1, &indexCopy);
	});

	destroy_buffer(staging);


}