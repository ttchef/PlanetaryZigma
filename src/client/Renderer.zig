const Renderer = @This();
const std = @import("std");
const Metal = @import("renderer/MetalRenderer.zig");
const Vulkan = @import("renderer/VulkanRenderer.zig");


inner: Inner,

pub const Inner = switch (std.builtin.os.tag) {
    .macos => Metal,
    else => Vulkan,
};

pub fn init(renderer: *Renderer) !void {

    switch (std.builtin.os.tag) {
        .macos => 
    }
    _ = renderer;
}

pub fn deinit(renderer: *Renderer) !void {
    _ = renderer;
}

pub fn update(renderer: *Renderer) !void {
    _ = renderer;
}
