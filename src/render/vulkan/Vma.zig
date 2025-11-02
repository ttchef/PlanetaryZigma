const vma = @import("vma");
const vk = @import("vulkan.zig");

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
