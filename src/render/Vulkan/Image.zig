const vk = @import("vulkan.zig");
const vma = @import("vma");

image: vk.c.VkImage = undefined,
image_view: vk.c.VkImageView = undefined,
vma_allocation: vma.VmaAllocation = undefined,
image_extent: vk.c.VkExtent3D = undefined,
format: vk.c.VkFormat = undefined,
