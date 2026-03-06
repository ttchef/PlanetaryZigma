const std = @import("std");
pub const c = @import("vma");
// const vulkanC = @import("vulkan");
const Instance = @import("Instance.zig");
const PhysicalDevice = @import("device.zig").Physical;
const Device = @import("device.zig").Logical;
const check = @import("utils.zig").check;

pub const Allocator = c.VmaAllocator;
pub const Allocation = c.VmaAllocation;
pub const AllocationInfo = c.VmaAllocationInfo;

handle: c.VmaAllocator = undefined,

pub fn init(instance: Instance, physical_device: PhysicalDevice, device: Device) !@This() {
    var vma_info: c.VmaAllocatorCreateInfo = .{
        .physicalDevice = @ptrCast(physical_device.handle),
        .device = @ptrCast(device.handle),
        .instance = @ptrCast(instance.handle),
        .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };

    var vulkan_volk_functions: c.VmaVulkanFunctions = undefined;
    check(c.vmaImportVulkanFunctionsFromVolk(&vma_info, &vulkan_volk_functions));
    vma_info.pVulkanFunctions = &vulkan_volk_functions;

    var vulkan_mem_alloc: c.VmaAllocator = undefined;
    try check(c.vmaCreateAllocator(&vma_info, &vulkan_mem_alloc));

    return .{
        .handle = vulkan_mem_alloc,
    };
}

pub fn deinit(self: @This()) void {
    c.vmaDestroyAllocator(self.handle);
}

pub fn copyToAllocation(
    self: @This(),
    comptime T: type,
    src_data: T,
    dst_allocation: Allocation,
    allocation_info: *AllocationInfo,
) void {
    c.vmaGetAllocationInfo(self.handle, dst_allocation, allocation_info);
    @memcpy(
        @as([*]u8, @ptrCast(allocation_info.pMappedData))[0..@intCast(allocation_info.size)],
        @as([*]const u8, @ptrCast(&src_data))[0..@intCast(allocation_info.size)],
    );
}
