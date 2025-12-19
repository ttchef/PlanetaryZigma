const std = @import("std");
const vk = @import("vulkan.zig");
buffer: vk.c.VkBuffer,
vma_allocation: vk.Vma.Allocation,
info: vk.Vma.AllocationInfo,

pub fn init(vma_allocator: vk.Vma.Allocator, size: usize, vk_usage: vk.c.VkBufferUsageFlags, vma_usage: vk.Vma.c.VmaMemoryUsage) !@This() {
    var buffer_info: vk.Vma.c.VkBufferCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = vk_usage,
    };
    var vmaalloc_info: vk.Vma.c.VmaAllocationCreateInfo = .{
        .usage = vma_usage,
        .flags = vk.Vma.c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
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

    std.debug.print("INIT BUFFER PTR: {*}\n", .{new_buffer});

    return .{
        .buffer = new_buffer,
        .vma_allocation = allocation,
        .info = info,
    };
}

pub fn deinit(self: @This(), vma_allocator: vk.Vma.Allocator) void {
    std.debug.print("DENINIT PTR: {*}\n", .{self.buffer});

    vk.Vma.c.vmaDestroyBuffer(vma_allocator, @ptrCast(self.buffer), self.vma_allocation);
}
