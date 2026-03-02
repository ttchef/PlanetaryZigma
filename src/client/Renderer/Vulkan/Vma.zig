const std = @import("std");
const vma = @import("vma");
const Instance = @import("Instance.zig");
const PhysicalDevice = @import("device.zig").Physical;
const Device = @import("device.zig").Logical;
const check = @import("utils.zig").check;

pub const Allocator = vma.VmaAllocator;
pub const Allocation = vma.VmaAllocation;
pub const AllocationInfo = vma.VmaAllocationInfo;

handle: vma.VmaAllocator = undefined,

pub fn init(instance: Instance, physical_device: PhysicalDevice, device: Device) !@This() {
    var vma_info: vma.VmaAllocatorCreateInfo = .{
        .physicalDevice = @ptrCast(physical_device.handle),
        .device = @ptrCast(device.handle),
        .instance = @ptrCast(instance.handle),
        .flags = vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };

    var vulkan_mem_alloc: vma.VmaAllocator = undefined;
    try check(vma.vmaCreateAllocator(&vma_info, &vulkan_mem_alloc));

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
    src_data: T,
    dst_allocation: Allocation,
    allocation_info: *AllocationInfo,
) void {
    vma.vmaGetAllocationInfo(self.handle, dst_allocation, allocation_info);
    @memcpy(
        @as([*]u8, @ptrCast(allocation_info.pMappedData))[0..@intCast(allocation_info.size)],
        @as([*]const u8, @ptrCast(&src_data))[0..@intCast(allocation_info.size)],
    );
}
