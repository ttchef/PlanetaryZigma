const vk = @import("vulkan.zig");
const vma = @import("vma");

buffer: vk.c.VkBuffer = undefined,
vma_allocation: vma.VmaAllocation = undefined,
VmaAllocationInfo info;


