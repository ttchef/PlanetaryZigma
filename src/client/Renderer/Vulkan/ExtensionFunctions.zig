const std = @import("std");
const c = @import("vulkan");

// Instance-level extension functions
pub var vkCreateDebugUtilsMessengerEXT: *const fn (c.VkInstance, *const c.VkDebugUtilsMessengerCreateInfoEXT, ?*const anyopaque, *c.VkDebugUtilsMessengerEXT) callconv(.c) c.VkResult = undefined;
pub var vkDestroyDebugUtilsMessengerEXT: *const fn (c.VkInstance, c.VkDebugUtilsMessengerEXT, ?*const anyopaque) callconv(.c) void = undefined;

// Device-level extension functions
pub var vkCreateShadersEXT: *const fn (c.VkDevice, u32, *const c.VkShaderCreateInfoEXT, ?*const anyopaque, *c.VkShaderEXT) callconv(.c) c.VkResult = undefined;
pub var vkDestroyShaderEXT: *const fn (c.VkDevice, c.VkShaderEXT, ?*const anyopaque) callconv(.c) void = undefined;
pub var vkCmdBindShadersEXT: *const fn (c.VkCommandBuffer, u32, [*c]const c.VkShaderStageFlagBits, [*c]const c.VkShaderEXT) callconv(.c) void = undefined;
pub var vkCmdSetViewportWithCountEXT: *const fn (c.VkCommandBuffer, u32, [*c]const c.VkViewport) callconv(.c) void = undefined;
pub var vkCmdSetScissorWithCountEXT: *const fn (c.VkCommandBuffer, u32, [*c]const c.VkRect2D) callconv(.c) void = undefined;
pub var vkCmdSetCullModeEXT: *const fn (c.VkCommandBuffer, c.VkCullModeFlags) callconv(.c) void = undefined;
pub var vkCmdSetFrontFaceEXT: *const fn (c.VkCommandBuffer, c.VkFrontFace) callconv(.c) void = undefined;
pub var vkCmdSetDepthTestEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetDepthWriteEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetDepthCompareOpEXT: *const fn (c.VkCommandBuffer, c.VkCompareOp) callconv(.c) void = undefined;
pub var vkCmdSetPrimitiveTopologyEXT: *const fn (c.VkCommandBuffer, c.VkPrimitiveTopology) callconv(.c) void = undefined;
pub var vkCmdSetRasterizerDiscardEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetPolygonModeEXT: *const fn (c.VkCommandBuffer, c.VkPolygonMode) callconv(.c) void = undefined;
pub var vkCmdSetRasterizationSamplesEXT: *const fn (c.VkCommandBuffer, c.VkSampleCountFlagBits) callconv(.c) void = undefined;
pub var vkCmdSetAlphaToCoverageEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetDepthBiasEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetStencilTestEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetPrimitiveRestartEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetSampleMaskEXT: *const fn (c.VkCommandBuffer, c.VkSampleCountFlagBits, [*c]const u32) callconv(.c) void = undefined;
pub var vkCmdSetColorBlendEnableEXT: *const fn (c.VkCommandBuffer, u32, u32, [*c]const c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetColorWriteMaskEXT: *const fn (c.VkCommandBuffer, u32, u32, [*c]const c.VkColorComponentFlags) callconv(.c) void = undefined;
pub var vkCmdSetDepthBoundsTestEnable: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetDepthClampEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetAlphaToOneEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetLogicOpEnableEXT: *const fn (c.VkCommandBuffer, c.VkBool32) callconv(.c) void = undefined;
pub var vkCmdSetVertexInputEXT: *const fn (c.VkCommandBuffer, u32, [*c]const c.VkVertexInputBindingDescription2EXT, u32, [*c]const c.VkVertexInputAttributeDescription2EXT) callconv(.c) void = undefined;
pub var vkCmdBeginRendering: *const fn (c.VkCommandBuffer, [*c]const c.VkRenderingInfo) callconv(.c) void = undefined;
pub var vkCmdEndRendering: *const fn (c.VkCommandBuffer) callconv(.c) void = undefined;

fn loadFunction(comptime FuncType: type, proc_addr: ?*const anyopaque) FuncType {
    return @ptrCast(proc_addr orelse {
        @panic("Failed to load Vulkan extension function");
    });
}

pub fn loadInstanceFunctions(instance: c.VkInstance) void {
    vkCreateDebugUtilsMessengerEXT = loadFunction(@TypeOf(vkCreateDebugUtilsMessengerEXT), c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    vkDestroyDebugUtilsMessengerEXT = loadFunction(@TypeOf(vkDestroyDebugUtilsMessengerEXT), c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
}

pub fn loadDeviceFunctions(device: c.VkDevice) void {
    vkCreateShadersEXT = loadFunction(@TypeOf(vkCreateShadersEXT), c.vkGetDeviceProcAddr(device, "vkCreateShadersEXT"));
    vkDestroyShaderEXT = loadFunction(@TypeOf(vkDestroyShaderEXT), c.vkGetDeviceProcAddr(device, "vkDestroyShaderEXT"));
    vkCmdBindShadersEXT = loadFunction(@TypeOf(vkCmdBindShadersEXT), c.vkGetDeviceProcAddr(device, "vkCmdBindShadersEXT"));
    vkCmdSetViewportWithCountEXT = loadFunction(@TypeOf(vkCmdSetViewportWithCountEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetViewportWithCountEXT"));
    vkCmdSetScissorWithCountEXT = loadFunction(@TypeOf(vkCmdSetScissorWithCountEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetScissorWithCountEXT"));
    vkCmdSetCullModeEXT = loadFunction(@TypeOf(vkCmdSetCullModeEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetCullModeEXT"));
    vkCmdSetFrontFaceEXT = loadFunction(@TypeOf(vkCmdSetFrontFaceEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetFrontFaceEXT"));
    vkCmdSetDepthTestEnableEXT = loadFunction(@TypeOf(vkCmdSetDepthTestEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetDepthTestEnableEXT"));
    vkCmdSetDepthWriteEnableEXT = loadFunction(@TypeOf(vkCmdSetDepthWriteEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetDepthWriteEnableEXT"));
    vkCmdSetDepthCompareOpEXT = loadFunction(@TypeOf(vkCmdSetDepthCompareOpEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetDepthCompareOpEXT"));
    vkCmdSetPrimitiveTopologyEXT = loadFunction(@TypeOf(vkCmdSetPrimitiveTopologyEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetPrimitiveTopologyEXT"));
    vkCmdSetRasterizerDiscardEnableEXT = loadFunction(@TypeOf(vkCmdSetRasterizerDiscardEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetRasterizerDiscardEnableEXT"));
    vkCmdSetPolygonModeEXT = loadFunction(@TypeOf(vkCmdSetPolygonModeEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetPolygonModeEXT"));
    vkCmdSetRasterizationSamplesEXT = loadFunction(@TypeOf(vkCmdSetRasterizationSamplesEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetRasterizationSamplesEXT"));
    vkCmdSetAlphaToCoverageEnableEXT = loadFunction(@TypeOf(vkCmdSetAlphaToCoverageEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetAlphaToCoverageEnableEXT"));
    vkCmdSetDepthBiasEnableEXT = loadFunction(@TypeOf(vkCmdSetDepthBiasEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetDepthBiasEnableEXT"));
    vkCmdSetStencilTestEnableEXT = loadFunction(@TypeOf(vkCmdSetStencilTestEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetStencilTestEnableEXT"));
    vkCmdSetPrimitiveRestartEnableEXT = loadFunction(@TypeOf(vkCmdSetPrimitiveRestartEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetPrimitiveRestartEnableEXT"));
    vkCmdSetSampleMaskEXT = loadFunction(@TypeOf(vkCmdSetSampleMaskEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetSampleMaskEXT"));
    vkCmdSetColorBlendEnableEXT = loadFunction(@TypeOf(vkCmdSetColorBlendEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetColorBlendEnableEXT"));
    vkCmdSetColorWriteMaskEXT = loadFunction(@TypeOf(vkCmdSetColorWriteMaskEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetColorWriteMaskEXT"));
    vkCmdSetDepthBoundsTestEnable = loadFunction(@TypeOf(vkCmdSetDepthBoundsTestEnable), c.vkGetDeviceProcAddr(device, "vkCmdSetDepthBoundsTestEnable"));
    vkCmdSetDepthClampEnableEXT = loadFunction(@TypeOf(vkCmdSetDepthClampEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetDepthClampEnableEXT"));
    vkCmdSetAlphaToOneEnableEXT = loadFunction(@TypeOf(vkCmdSetAlphaToOneEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetAlphaToOneEnableEXT"));
    vkCmdSetLogicOpEnableEXT = loadFunction(@TypeOf(vkCmdSetLogicOpEnableEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetLogicOpEnableEXT"));
    vkCmdSetVertexInputEXT = loadFunction(@TypeOf(vkCmdSetVertexInputEXT), c.vkGetDeviceProcAddr(device, "vkCmdSetVertexInputEXT"));
    vkCmdBeginRendering = loadFunction(@TypeOf(vkCmdBeginRendering), c.vkGetDeviceProcAddr(device, "vkCmdBeginRendering"));
    vkCmdEndRendering = loadFunction(@TypeOf(vkCmdEndRendering), c.vkGetDeviceProcAddr(device, "vkCmdEndRendering"));
}
