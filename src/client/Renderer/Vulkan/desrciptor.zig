const std = @import("std");
const c = @import("vulkan.zig");
const Func = @import("utils.zig").Func;
const Device = @import("device.zig").Logical;
const check = @import("utils.zig").check;

pub const Layout = struct {
    handle: c.VkDescriptorSetLayout,

    pub fn init(device: Device, bindings: []const c.VkDescriptorSetLayoutBinding) !@This() {
        var info: c.VkDescriptorSetLayoutCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pBindings = &bindings[0],
            .bindingCount = @intCast(bindings.len),
        };

        var set: c.VkDescriptorSetLayout = undefined;
        try check(c.vkCreateDescriptorSetLayout.?(device.handle, &info, null, &set));
        return .{ .handle = set };
    }

    pub fn deinit(self: @This(), device: Device) void {
        c.vkDestroyDescriptorSetLayout.?(device.handle, self.handle, null);
    }
};
