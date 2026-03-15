const std = @import("std");
const c = @import("vulkan");
const Vma = @import("Vma.zig");
const check = @import("utils.zig").check;

buffer: c.VkBuffer,
vma_allocation: Vma.Allocation,
info: Vma.AllocationInfo,

pub fn init(vma: Vma, size: usize, vk_buffer_usage: c.VkBufferUsageFlags, vmaalloc_info: Vma.c.VmaAllocationCreateInfo) !@This() {
    var buffer_info: Vma.c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = vk_buffer_usage,
    };

    var new_buffer: c.VkBuffer = undefined;
    var allocation: Vma.Allocation = undefined;
    var info: Vma.AllocationInfo = undefined;

    try check(Vma.c.vmaCreateBuffer(
        vma.handle,
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

pub fn deinit(self: @This(), vma: Vma) void {
    Vma.c.vmaDestroyBuffer(vma.handle, @ptrCast(self.buffer), self.vma_allocation);
}

pub fn copy(self: *@This(), comptime T: type, data: *const T, amount: usize) void {
    const size = @sizeOf(T) * amount;
    std.debug.assert(size <= self.info.size);
    var mapped: [*]u8 = @ptrCast(self.info.pMappedData);
    var byte_data: [*]const u8 = @ptrCast(data);
    @memcpy(
        mapped[0..size],
        byte_data[0..size],
    );
}
