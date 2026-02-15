const std = @import("std");
const vk = @import("vulkan.zig");
buffer: vk.c.VkBuffer,
vma_allocation: vk.Vma.Allocation,
info: vk.Vma.AllocationInfo,

pub fn init(vma_allocator: vk.Vma.Allocator, size: usize, vk_usage: vk.c.VkBufferUsageFlags, vmaalloc_info: vk.Vma.c.VmaAllocationCreateInfo) !@This() {
    var buffer_info: vk.Vma.c.VkBufferCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = vk_usage,
    };

    var new_buffer: vk.c.VkBuffer = undefined;
    var allocation: vk.Vma.Allocation = undefined;
    var info: vk.Vma.AllocationInfo = undefined;

    try vk.check(vk.Vma.c.vmaCreateBuffer(
        vma_allocator,
        &buffer_info,
        &vmaalloc_info,
        @ptrCast(&new_buffer),
        &allocation,
        &info,
    ));

    return .{
        .buffer = new_buffer,
        .vma_allocation = allocation,
        .info = info,
    };
}

pub fn deinit(self: @This(), vma_allocator: vk.Vma.Allocator) void {
    vk.Vma.c.vmaDestroyBuffer(vma_allocator, @ptrCast(self.buffer), self.vma_allocation);
}
