const std = @import("std");
const c = @import("vulkan");
const Instance = @import("Instance.zig");
const Func = @import("utils.zig").Func;
const check = @import("utils.zig").check;

handle: c.VkDebugUtilsMessengerEXT,

pub const Config = struct {
    severities: struct {
        verbose: bool = false,
        warning: bool = false,
        @"error": bool = false,
        info: bool = false,
    } = .{},
};

pub fn init(instance: Instance, config: Config) !@This() {
    var message_severity: u32 = 0;
    if (config.severities.verbose) message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;
    if (config.severities.warning) message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT;
    if (config.severities.@"error") message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    if (config.severities.info) message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT;

    const message_type: u32 = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;

    var create_info: c.VkDebugUtilsMessengerCreateInfoEXT = .{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .pNext = null,
        .flags = 0,
        .messageSeverity = message_severity,
        .messageType = message_type,
        .pfnUserCallback = callback,
        .pUserData = null,
    };

    var messenger: c.VkDebugUtilsMessengerEXT = undefined;
    const createDebugUtilsMessengerExt = try Func.Proc(.createDebugUtilsMessengerEXT).load(instance);
    try check(createDebugUtilsMessengerExt(instance.handle, &create_info, null, &messenger));

    return .{ .handle = messenger };
}

pub fn deinit(self: @This(), instance: Instance) void {
    const destroyDebugUtilsMessenger = Func.Proc(.destroyDebugUtilsMessengerEXT).load(instance) catch unreachable;
    destroyDebugUtilsMessenger(instance.handle, self.handle, null);
}

fn callback(severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT, _: c.VkDebugUtilsMessageTypeFlagsEXT, callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) c.VkBool32 {
    //NOTE: for deperate times if Vulkan Validation layers crashes.
    // const cc = @cImport({
    //     @cInclude("vulkan/vulkan.h");
    //     @cInclude("stdio.h");
    // });
    // const cbd = callback_data orelse return c.VK_FALSE;
    // const msg_ptr = cbd.*.pMessage;
    // const msg: []const u8 = if (msg_ptr != null) std.mem.span(msg_ptr) else "<null>";
    _ = switch (severity) {
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => _ = std.c.printf("VK:  %s\n", callback_data.*.pMessage),
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => _ = std.c.printf("VK:  %s\n", callback_data.*.pMessage),
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => _ = std.c.printf("VK:  %s\n", callback_data.*.pMessage),
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => _ = std.c.printf("VK:  %s\n", callback_data.*.pMessage),
        else => unreachable,
    };

    return c.VK_FALSE;
}
