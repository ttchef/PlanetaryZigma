const vk = @import("vulkan.zig");
const vma = @import("vma");
buffer: vk.c.VkBuffer,
vma_allocation: vma.VmaAllocation,
info: vma.VmaAllocationInfo,

pub fn init(vma_allocation: vma.VmaAllocation, size: usize, vk_usage: vk.c.VkBufferUsageFlags, vma_usage: vma.VmaMemoryUsage) !void {
    var buffer_info: vk.v.VkBufferCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = vk_usage,
    };
    var vmaalloc_info: vk.c.VmaAllocationCreateInfo = .{
        .usage = vma_usage,
        .flags = vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    };

    var new_buffer: vk.c.VkBuffer = undefined;
    var allocation: vma.VmaAllocation = undefined;
    var info: vma.VmaAllocationInfo = undefined;

    try vk.check(vma.vmaCreateBuffer(
        vma_allocation,
        &buffer_info,
        &vmaalloc_info,
        &new_buffer,
        &allocation,
        &info,
    ));

    return .{
        .buffer = new_buffer,
        .vma_allocation = allocation,
        .info = info,
    };
}
