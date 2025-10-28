const std = @import("std");

pub const c = @import("vulkan");
pub const check = @import("utils.zig").check;
pub const Func = @import("utils.zig").Func;
pub const LoadShader = @import("utils.zig").loadShaderModule;
pub const imageMemBarrier = @import("utils.zig").imageMemBarrier;
pub const copyImageToImage = @import("utils.zig").copyImageToImage;

pub const Swapchain = @import("Swapchain.zig");
pub const Image = @import("Image.zig");
pub const Vma = @import("Vma.zig");
pub const Descriptor = @import("Descriptor.zig");
pub const Pipeline = @import("pipeline.zig").Pipeline;

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
        switch (severity) {
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => std.log.info("VK:\n{s}\n", .{callback_data.*.pMessage}),
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => std.log.info("VK:\n{s}\n", .{callback_data.*.pMessage}),
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => std.log.warn("VK:\n{s}\n", .{callback_data.*.pMessage}),
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => std.log.err("VK:\n{s}\n", .{callback_data.*.pMessage}),
            else => unreachable,
        }

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

pub const PhysicalDevice = struct {
    handle: c.VkPhysicalDevice,
    queue_family_index: u32,

    pub fn find(instance: Instance, surface: Surface) !@This() {
        var device_count: u32 = 0;
        try check(c.vkEnumeratePhysicalDevices(instance.handle, &device_count, null));
        if (device_count == 0) return error.NoPhysicalDevices;

        var devices: [8]c.VkPhysicalDevice = undefined;
        try check(c.vkEnumeratePhysicalDevices(instance.handle, &device_count, &devices));

        for (devices[0..device_count]) |device| {
            var properties: c.VkPhysicalDeviceProperties = undefined;
            c.vkGetPhysicalDeviceProperties(device, &properties);

            var family_count: u32 = 0;
            c.vkGetPhysicalDeviceQueueFamilyProperties(device, &family_count, null);

            var families: [16]c.VkQueueFamilyProperties = undefined;
            c.vkGetPhysicalDeviceQueueFamilyProperties(device, &family_count, &families);

            for (families[0..family_count], 0..) |family, i| {
                const supports_graphics = (family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0;

                var present_supported: c.VkBool32 = undefined;
                try check(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface.handle, &present_supported));

                if (supports_graphics and present_supported != 0) {
                    std.log.info("Picked device: {s}, queue family: {d}\n", .{ properties.deviceName, i });

                    return .{ .handle = device, .queue_family_index = @intCast(i) };
                }
            }
        }
        return error.NoSuitablePhysicalDevice;
    }
};

pub const Device = struct {
    handle: c.VkDevice,

    pub fn init(physical_device: PhysicalDevice, extensions: ?[]const [*:0]const u8) !@This() {
        var extension_count: u32 = undefined;
        try check(c.vkEnumerateDeviceExtensionProperties(physical_device.handle, null, &extension_count, null));
        var extension_properties: [516]c.VkExtensionProperties = undefined;
        try check(c.vkEnumerateDeviceExtensionProperties(physical_device.handle, null, &extension_count, &extension_properties));
        check_ext: for (extensions orelse &.{}) |extension| {
            for (extension_properties[0..extension_count]) |cmp_ext|
                if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&cmp_ext.extensionName, 0))) continue :check_ext;
            std.log.err("Missing Device extention: {s}\n", .{extension});
            return error.MissingDeviceExtension;
        }

        // var dynamic_rendering_features: c.VkPhysicalDeviceDynamicRenderingFeatures = .{
        //     .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
        //     .dynamicRendering = c.VK_TRUE,
        // };

        var queue_priority: f32 = 1.0;
        const queue_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            // .pNext = &dynamic_rendering_features,
            .pNext = null,
            .queueFamilyIndex = physical_device.queue_family_index,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
            .flags = 0,
        };

        var features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(physical_device.handle, &features);

        var dynamic_rendering_features: c.VkPhysicalDeviceDynamicRenderingFeatures = .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
            .pNext = null,
            .dynamicRendering = c.VK_TRUE,
        };

        var sync2_features: c.VkPhysicalDeviceSynchronization2Features = .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,
            .pNext = &dynamic_rendering_features,
            .synchronization2 = c.VK_TRUE,
        };

        var buffer_device_address_features = c.VkPhysicalDeviceBufferDeviceAddressFeatures{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES,
            .pNext = &sync2_features,
            .bufferDeviceAddress = c.VK_TRUE,
        };

        const device_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = &buffer_device_address_features,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_info,
            .pEnabledFeatures = &features,
            .enabledExtensionCount = if (extensions != null) @intCast(extensions.?.len) else 0,
            .ppEnabledExtensionNames = if (extensions != null) extensions.?.ptr else null,
        };

        var device: c.VkDevice = undefined;
        try check(c.vkCreateDevice(physical_device.handle, &device_info, null, &device));
        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physical_device.queue_family_index, 0, &queue);

        return .{ .handle = device };
    }

    pub fn deinit(self: @This()) void {
        c.vkDestroyDevice(self.handle, null);
    }

    pub inline fn getQueue(self: @This(), index: u32) c.VkQueue {
        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(self.handle, index, 0, &queue);
        return queue;
    }
};

pub const CommandPool = struct {
    handle: c.VkCommandPool,

    pub fn init(device: Device, queue_family_index: u32) !@This() {
        const command_pool_info: c.VkCommandPoolCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queue_family_index,
        };

        var command_pool: c.VkCommandPool = undefined;
        try check(c.vkCreateCommandPool(device.handle, &command_pool_info, null, &command_pool));
        return .{ .handle = command_pool };
    }

    pub fn deinit(self: @This(), device: Device) void {
        c.vkDestroyCommandPool(device.handle, self.handle, null);
    }
};
