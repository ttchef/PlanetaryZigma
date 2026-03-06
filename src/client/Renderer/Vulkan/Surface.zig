const std = @import("std");
const Instance = @import("Instance.zig");
pub const c = @import("vulkan");

handle: c.VkSurfaceKHR,

pub fn deinit(self: @This(), instance: Instance) void {
    c.vkDestroySurfaceKHR.?(instance.handle, self.handle, null);
}
