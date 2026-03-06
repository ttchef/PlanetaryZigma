const std = @import("std");
const c = @import("vulkan");
const check = @import("utils.zig").check;

handle: c.VkInstance,

pub fn init(extensions: []const [*:0]const u8, layers: []const [*:0]const u8) !@This() {
    var extension_count: u32 = undefined;
    try check(c.vkEnumerateInstanceExtensionProperties.?(null, &extension_count, null));
    var extension_properties: [128]c.VkExtensionProperties = undefined;
    try check(c.vkEnumerateInstanceExtensionProperties.?(null, &extension_count, &extension_properties));
    check_ext: for (extensions) |extension| {
        std.debug.print("ext: {s}\n", .{extension});
        for (extension_properties[0..extension_count]) |cmp_ext| {
            if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&cmp_ext.extensionName, 0))) continue :check_ext;
        }
        std.log.err("Missing instance extention: {s}\n", .{extension});
        return error.MissingInstanceExtension;
    }

    var layer_count: u32 = undefined;
    try check(c.vkEnumerateInstanceLayerProperties.?(&layer_count, null));
    var layer_properties: [128]c.VkLayerProperties = undefined;
    try check(c.vkEnumerateInstanceLayerProperties.?(&layer_count, &layer_properties));
    check_layer: for (layers) |layer| {
        for (layer_properties[0..layer_count]) |cmp_layer|
            if (std.mem.eql(u8, std.mem.span(layer), std.mem.sliceTo(&cmp_layer.layerName, 0))) continue :check_layer;
        std.log.err("Missing instance layer: {s}\n", .{layer});
        return error.MissingInstanceLayer;
    }

    var create_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .ppEnabledExtensionNames = extensions.ptr,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledLayerNames = layers.ptr,
        .enabledLayerCount = @intCast(layers.len),

        .pApplicationInfo = &.{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "PlanetaryZigma",
            .pEngineName = "Engine",
            .apiVersion = c.VK_API_VERSION_1_4,
        },
    };

    var instance: c.VkInstance = undefined;
    try check(c.vkCreateInstance.?(&create_info, null, &instance));
    return .{ .handle = instance };
}

pub fn deinit(self: @This()) void {
    c.vkDestroyInstance.?(self.handle, null);
}
