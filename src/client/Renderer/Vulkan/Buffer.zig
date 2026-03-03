const std = @import("std");
const c = @import("vulkan");
const Vma = @import("Vma.zig");
const check = @import("utils.zig").check;

buffer: c.VkBuffer,
vma_allocation: Vma.Allocation,
info: Vma.AllocationInfo,

pub fn init(vma_allocator: Vma.Allocator, size: usize, vk_usage: c.VkBufferUsageFlags, vmaalloc_info: Vma.c.VmaAllocationCreateInfo) !@This() {
    var buffer_info: Vma.c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = vk_usage,
    };

    var new_buffer: c.VkBuffer = undefined;
    var allocation: Vma.Allocation = undefined;
    var info: Vma.AllocationInfo = undefined;

    try check(Vma.c.vmaCreateBuffer(
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

pub fn deinit(self: @This(), vma_allocator: Vma.Allocator) void {
    Vma.c.vmaDestroyBuffer(vma_allocator, @ptrCast(self.buffer), self.vma_allocation);
}
