const std = @import("std");

pub const c = @import("vulkan");
pub const check = @import("utils.zig").check;
pub const Func = @import("utils.zig").Func;
pub const imageMemBarrier = @import("utils.zig").imageMemBarrier;
pub const copyImageToImage = @import("utils.zig").copyImageToImage;

pub const Swapchain = @import("Swapchain.zig");
pub const Image = @import("Image.zig");
pub const Vma = @import("Vma.zig");
pub const Descriptor = @import("Descriptor.zig");
pub const Pipeline: type = @import("Pipeline.zig");

pub const Instance = opaque {
    pub inline fn toC(self: *@This()) c.VkInstance {
        return @ptrCast(self);
    }

    pub fn init(extensions: ?[]const [*:0]const u8, layers: ?[]const [*:0]const u8) !*@This() {
        // TODO: Add checks so no invalid extensions or layers get past

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
        return @ptrCast(instance);
    }

    pub fn deinit(self: *@This()) void {
        c.vkDestroyInstance(self.toC(), null);
    }
};

pub const DebugMessenger = opaque {
    pub inline fn toC(self: *@This()) c.VkDebugUtilsMessengerEXT {
        return @ptrCast(self);
    }

    pub const Config = struct {
        severities: struct {
            verbose: bool = true,
            warning: bool = true,
            @"error": bool = true,
        } = .{},
    };

    pub fn init(instance: *Instance, config: Config) !*@This() {
        // zig fmt: off
        const message_severity: u32 = @intCast(
            if (config.severities.verbose) c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT else 0 |
            if (config.severities.warning) c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT else 0 |
            if (config.severities.@"error") c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT else 0);
        // zig fmt: on

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
        try check(createDebugUtilsMessengerExt(instance.toC(), &create_info, null, &messenger));

        return @ptrCast(messenger);
    }

    pub fn deinit(self: *@This(), instance: *Instance) void {
        const destroyDebugUtilsMessenger = Func.Proc(.destroyDebugUtilsMessengerEXT).load(instance) catch unreachable;
        destroyDebugUtilsMessenger(instance.toC(), self.toC(), null);
    }

    fn callback(severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT, _: c.VkDebugUtilsMessageTypeFlagsEXT, callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) c.VkBool32 {
        switch (severity) {
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT => std.log.info("VK {s}", .{callback_data.*.pMessage}),
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT => std.log.info("VK {s}", .{callback_data.*.pMessage}),
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT => std.log.warn("VK {s}", .{callback_data.*.pMessage}),
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT => std.log.err("VK {s}", .{callback_data.*.pMessage}),
            else => unreachable,
        }

        return c.VK_FALSE;
    }
};

pub const Surface = opaque {
    pub inline fn toC(self: *@This()) c.VkSurfaceKHR {
        return @ptrCast(self);
    }

    pub fn init(_: *Instance) !*@This() {
        // TODO: Make not hard coded and allow for other windowing libraries

        @panic("Not implemented use the surface sub config instead");
        // return @ptrCast(null);
    }

    pub fn deinit(self: *@This(), instance: *Instance) void {
        c.vkDestroySurfaceKHR(instance.toC(), self.toC(), null);
    }
};

pub const PhysicalDevice = struct {
    ptr: c.VkPhysicalDevice,
    queue_family_index: u32,

    pub fn find(instance: *Instance, surface: *Surface) !@This() {
        var device_count: u32 = 0;
        try check(c.vkEnumeratePhysicalDevices(instance.toC(), &device_count, null));
        if (device_count == 0) return error.NoPhysicalDevices;

        var devices: [8]c.VkPhysicalDevice = undefined;
        try check(c.vkEnumeratePhysicalDevices(instance.toC(), &device_count, &devices));

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
                try check(c.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface.toC(), &present_supported));

                if (supports_graphics and present_supported != 0) {
                    std.log.info("Picked device: {s}, queue family: {d}\n", .{ properties.deviceName, i });

                    return .{ .ptr = device, .queue_family_index = @intCast(i) };
                }
            }
        }
        return error.NoSuitablePhysicalDevice;
    }
};

pub const Device = opaque {
    pub inline fn toC(self: *@This()) c.VkDevice {
        return @ptrCast(self);
    }

    pub const Queue = opaque {
        pub inline fn toC(self: *Queue) c.VkQueue {
            return @ptrCast(self);
        }
    };

    pub fn init(physical_device: PhysicalDevice, extensions: ?[]const [*:0]const u8) !*@This() {
        var dynamic_rendering_features: c.VkPhysicalDeviceDynamicRenderingFeatures = .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
            .dynamicRendering = c.VK_TRUE,
        };

        var queue_priority: f32 = 1.0;
        const queue_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = &dynamic_rendering_features,
            .queueFamilyIndex = physical_device.queue_family_index,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
            .flags = 0,
        };

        var features: c.VkPhysicalDeviceFeatures = undefined;
        c.vkGetPhysicalDeviceFeatures(physical_device.ptr, &features);

        const device_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_info,
            .pEnabledFeatures = &features,
            .enabledExtensionCount = if (extensions != null) @intCast(extensions.?.len) else 0,
            .ppEnabledExtensionNames = if (extensions != null) extensions.?.ptr else null,
        };

        var device: c.VkDevice = undefined;
        try check(c.vkCreateDevice(physical_device.ptr, &device_info, null, &device));
        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, physical_device.queue_family_index, 0, &queue);

        return @ptrCast(device);
    }

    pub fn deinit(self: *@This()) void {
        c.vkDestroyDevice(self.toC(), null);
    }

    pub inline fn getQueue(self: *@This(), index: u32) *Queue {
        var queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(self.toC(), index, 0, &queue);
        return @ptrCast(queue);
    }
};

pub const CommandPool = opaque {
    pub inline fn toC(self: *@This()) c.VkCommandPool {
        return @ptrCast(self);
    }

    pub fn init(device: *Device, queue_family_index: u32) !*@This() {
        const command_pool_info: c.VkCommandPoolCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = queue_family_index,
        };

        var command_pool: c.VkCommandPool = undefined;
        try check(c.vkCreateCommandPool(device.toC(), &command_pool_info, null, &command_pool));
        return @ptrCast(command_pool);
    }

    pub fn deinit(self: *@This(), device: *Device) void {
        c.vkDestroyCommandPool(device.toC(), self.toC(), null);
    }
};
