const vma = @import("vma");
const vk = @import("vulkan.zig");

vulkan_mem_alloc: vma.VmaAllocator = undefined,

pub fn init(instance: *vk.Instance, physical_device: vk.PhysicalDevice, device: *vk.Device) !@This() {
    var vma_info: vma.VmaAllocatorCreateInfo = .{
        .physicalDevice = @ptrCast(physical_device.ptr),
        .device = @ptrCast(device.toC()),
        .instance = @ptrCast(instance.toC()),
        .flags = vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
    };

    var vulkan_mem_alloc: vma.VmaAllocator = undefined;
    try vk.check(vma.vmaCreateAllocator(&vma_info, &vulkan_mem_alloc));

    return .{
        .vulkan_mem_alloc = vulkan_mem_alloc,
    };
}

pub fn deinit(self: @This()) void {
    vma.vmaDestroyAllocator(self.vulkan_mem_alloc);
}
