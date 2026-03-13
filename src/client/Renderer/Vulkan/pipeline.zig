const std = @import("std");
const c = @import("vulkan");
const Device = @import("device.zig").Logical;
const check = @import("utils.zig").check;

pub const Layout = struct {
    handle: c.VkPipelineLayout,
    pub fn init(device: Device, comptime PushConstant: type) !@This() {
        const ranges: c.VkPushConstantRange = .{
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
            .offset = 0,
            .size = @sizeOf(PushConstant),
        };

        var layout_create_info: c.VkPipelineLayoutCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            // .pSetLayouts = @ptrCast(config.descriptor_set_layouts),
            // .setLayoutCount = @intCast(config.descriptor_set_layouts.len),
            .pPushConstantRanges = &ranges,
            .pushConstantRangeCount = 1,
        };

        var layout: c.VkPipelineLayout = undefined;
        try check(c.vkCreatePipelineLayout(device.handle, &layout_create_info, null, &layout));
        return .{
            .handle = layout,
        };
    }
};
