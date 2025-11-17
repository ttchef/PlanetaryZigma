const std = @import("std");
const vk = @import("vulkan.zig");
const vma = @import("vma");
pub const c = vma;

pub const Allocator = c.VmaAllocator;
pub const Allocation = c.VmaAllocation;
pub const AllocationInfo = c.VmaAllocationInfo;

handle: vma.VmaAllocator = undefined,

pub fn init(instance: vk.Instance, physical_device: vk.PhysicalDevice, device: vk.Device) !@This() {
    var vma_info: vma.VmaAllocatorCreateInfo = .{
        .physicalDevice = @ptrCast(physical_device.handle),
        .device = @ptrCast(device.handle),
        .instance = @ptrCast(instance.handle),
        .flags = vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };

    var vulkan_mem_alloc: vma.VmaAllocator = undefined;
    try vk.check(vma.vmaCreateAllocator(&vma_info, &vulkan_mem_alloc));

    return .{
        .handle = vulkan_mem_alloc,
    };
}

pub fn deinit(self: @This()) void {
    vma.vmaDestroyAllocator(self.handle);
}

pub fn copyToAllocation(
    self: @This(),
    comptime T: type,
    data: T,
    allocation: Allocation,
    allocation_info: *AllocationInfo,
) void {
    vma.vmaGetAllocationInfo(self.handle, allocation, allocation_info);
    @memcpy(
        @as([*]u8, @ptrCast(allocation_info.pMappedData))[0..@intCast(allocation_info.size)],
        @as([*]const u8, @ptrCast(&data))[0..@intCast(allocation_info.size)],
    );
}
