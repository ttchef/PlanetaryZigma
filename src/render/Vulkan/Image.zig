const vk = @import("vulkan.zig");
const vma = @import("vma");

image: vk.c.VkImage = undefined,
imageView: vk.c.VkImageView = undefined,
allocation: vma.VmaAllocation = undefined,
imageExtent: vk.c.VkExtent3D = undefined,
imageFormat: vk.c.VkFormat = undefined,
