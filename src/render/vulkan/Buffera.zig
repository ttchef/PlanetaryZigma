const vk = @import("vulkan.zig");
// const vma = @import("vma");

// buffer: vk.c.VkBuffer,
// vma_allocation: vma.VmaAllocation = undefined,
// VmaAllocationInfo info;

pub fn init(size: usize, vk_usage: vk.c.VkBufferUsageFlags, vma_usage: vma.VmaMemoryUsage) !@This() {


}


// AllocatedBuffer VulkanEngine::create_buffer(size_t allocSize, VkBufferUsageFlags usage, VmaMemoryUsage memoryUsage)
// {
// 	// allocate buffer
// 	VkBufferCreateInfo bufferInfo = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
// 	bufferInfo.pNext = nullptr;
// 	bufferInfo.size = allocSize;

// 	bufferInfo.usage = usage;

// 	VmaAllocationCreateInfo vmaallocInfo = {};
// 	vmaallocInfo.usage = memoryUsage;
// 	vmaallocInfo.flags = VMA_ALLOCATION_CREATE_MAPPED_BIT;
// 	AllocatedBuffer newBuffer;

// 	// allocate the buffer
// 	VK_CHECK(vmaCreateBuffer(_allocator, &bufferInfo, &vmaallocInfo, &newBuffer.buffer, &newBuffer.allocation,
// 		&newBuffer.info));

// 	return newBuffer;
// }