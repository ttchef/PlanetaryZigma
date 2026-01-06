const std = @import("std");
const nz = @import("numz");

pub const c = @import("vulkan");
pub const check = @import("utils.zig").check;
pub const Func = @import("utils.zig").Func;
pub const LoadShader = @import("utils.zig").loadShaderModule;
pub const imageMemBarrier = @import("utils.zig").imageMemBarrier;
pub const blipImageToImage = @import("utils.zig").blitImageToImage;

pub const Device = @import("device.zig").Logical;
pub const PhysicalDevice = @import("device.zig").Physical;
pub const Swapchain = @import("Swapchain.zig");
pub const Image = @import("Image.zig");
pub const Vma = @import("Vma.zig");
pub const descriptor = @import("descriptor.zig");
pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Barrier = @import("Barrier.zig");
pub const Buffer = @import("Buffer.zig");
pub const Mesh = @import("Mesh.zig");
pub const Material = @import("Material.zig");
pub const Node = @import("Node.zig");

//TODO: WILL REMOVE (but exist temporarly for the learnding):
pub const GPUSceneData = extern struct {
    view: [16]f32,
    proj: [16]f32,
    viewproj: [16]f32,
    ambient_color: [4]f32,
    sunlight_direction: [4]f32,
    sunlight_color: [4]f32,
};

pub const Instance = struct {
    handle: c.VkInstance,

    pub fn init(extensions: ?[]const [*:0]const u8, layers: ?[]const [*:0]const u8) !@This() {
        var extension_count: u32 = undefined;
        try check(c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null));
        var extension_properties: [128]c.VkExtensionProperties = undefined;
        try check(c.vkEnumerateInstanceExtensionProperties(null, &extension_count, &extension_properties));
        check_ext: for (extensions orelse &.{}) |extension| {
            for (extension_properties[0..extension_count]) |cmp_ext| {
                if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&cmp_ext.extensionName, 0))) continue :check_ext;
            }
            std.log.err("Missing instance extention: {s}\n", .{extension});
            return error.MissingInstanceExtension;
        }

        var layer_count: u32 = undefined;
        try check(c.vkEnumerateInstanceLayerProperties(&layer_count, null));
        var layer_properties: [128]c.VkLayerProperties = undefined;
        try check(c.vkEnumerateInstanceLayerProperties(&layer_count, &layer_properties));
        check_layer: for (layers orelse &.{}) |layer| {
            for (layer_properties[0..layer_count]) |cmp_layer|
                if (std.mem.eql(u8, std.mem.span(layer), std.mem.sliceTo(&cmp_layer.layerName, 0))) continue :check_layer;
            std.log.err("Missing instance layer: {s}\n", .{layer});
            return error.MissingInstanceLayer;
        }

        var create_info: c.VkInstanceCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .ppEnabledExtensionNames = if (extensions != null) extensions.?.ptr else null,
            .enabledExtensionCount = if (extensions != null) @intCast(extensions.?.len) else 0,
            .ppEnabledLayerNames = if (layers != null) layers.?.ptr else null,
            .enabledLayerCount = if (layers != null) @intCast(layers.?.len) else 0,

            .pApplicationInfo = &.{
                .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .pApplicationName = "PlanetaryZigma",
                .pEngineName = "Engine",
                .apiVersion = c.VK_API_VERSION_1_3,
            },
        };

        var instance: c.VkInstance = undefined;
        try check(c.vkCreateInstance(&create_info, null, &instance));
        return .{ .handle = instance };
    }

    pub fn deinit(self: @This()) void {
        c.vkDestroyInstance(self.handle, null);
    }
};

pub const DebugMessenger = struct {
    handle: c.VkDebugUtilsMessengerEXT,

    pub const Config = struct {
        severities: struct {
            verbose: bool = true,
            warning: bool = true,
            @"error": bool = true,
            info: bool = true,
        } = .{},
    };

    pub fn init(instance: Instance, config: Config) !@This() {
        const running_renderdoc = std.process.hasEnvVarConstant("RENDERDOC_CAPFILE");

        var message_severity: u32 = 0;
        if (!running_renderdoc) {
            if (config.severities.verbose) message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT;
            if (config.severities.warning) message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT;
            if (config.severities.@"error") message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
            if (config.severities.info) message_severity |= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT;
        }
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
};

pub const Surface = struct {
    handle: c.VkSurfaceKHR,

    pub fn init(_: Instance) !@This() {
        // TODO: Make not hard coded and allow for other windowing libraries

        @panic("Not implemented use the surface sub config instead");
        // return @ptrCast(null);
    }

    pub fn deinit(self: @This(), instance: Instance) void {
        c.vkDestroySurfaceKHR(instance.handle, self.handle, null);
    }
};
