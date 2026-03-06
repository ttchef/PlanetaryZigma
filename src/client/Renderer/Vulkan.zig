const std = @import("std");
const AssetServer = @import("shared").AssetServer;
pub const c = @import("vulkan");
const Instance = @import("Vulkan/Instance.zig");
const DebugMessenger = @import("Vulkan/DebugMessenger.zig");
const PhysicalDevice = @import("Vulkan/device.zig").Physical;
const Device = @import("Vulkan/device.zig").Logical;
const Vma = @import("Vulkan/Vma.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");
const Surface = @import("Vulkan/Surface.zig");
const Image = @import("Vulkan/Image.zig");
pub const check = @import("Vulkan/utils.zig").check;

instance: Instance,
debug_messenger: DebugMessenger,
surface: Surface,
physical_device: PhysicalDevice,
device: Device,
vma: Vma,
swapchain: Swapchain,
draw_image: Image,
depth_image: Image,
shaders: [2]c.VkShaderEXT,

pub const Config = struct {
    instance: struct {
        extensions: []const [*:0]const u8,
        layers: []const [*:0]const u8,
    },
    device: struct {
        extensions: []const [*:0]const u8,
    },
    surface: struct {
        data: ?*anyopaque = null,
        init: ?*const fn (c.VkInstance, *anyopaque) anyerror!c.VkSurfaceKHR = null,
    } = .{},
    swapchain: struct {
        width: u32,
        heigth: u32,
    },
};

pub fn init(
    allocator: std.mem.Allocator,
    asset_server: *AssetServer,
    config: Config,
) !@This() {
    try check(c.volkInitialize());
    const instance: Instance = try .init(config.instance.extensions, config.instance.layers);
    c.volkLoadInstance(instance.handle);
    const debug_messenger: DebugMessenger = try .init(instance, .{
        .severities = if (try std.process.Environ.contains(.empty, allocator, "RENDERDOC_CAPFILE")) .{} else .{
            .warning = true,
            .verbose = true,
            .@"error" = true,
            .info = true,
        },
    });
    const surface: Surface = if (config.surface.init != null and config.surface.data != null) .{
        .handle = @ptrCast(try config.surface.init.?(instance.handle, config.surface.data.?)),
    } else return error.configSurface;
    const physical_device: PhysicalDevice = try .init(instance, surface.handle);
    const device: Device = try .init(physical_device, config.device.extensions);
    c.volkLoadDevice(device.handle);
    const vma: Vma = try .init(instance, physical_device, device);
    const swapchain: Swapchain = try .init(allocator, vma, physical_device, device, surface, config.swapchain.width, config.swapchain.heigth);
    const draw_image: Image = try .init(
        vma.handle,
        device,
        c.VK_FORMAT_R16G16B16A16_SFLOAT,
        swapchain.extent,
        c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    const depth_image: Image = try .init(
        vma.handle,
        device,
        c.VK_FORMAT_D32_SFLOAT,
        swapchain.extent,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        false,
    );

    const vert_data = try asset_server.loadAsset("shaders/vertex.vert.spv");
    const frag_data = try asset_server.loadAsset("shaders/fragment.frag.spv");
    const shader_create_info = &[_]c.VkShaderCreateInfoEXT{
        .{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .nextStage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = vert_data.len,
            .pCode = vert_data.ptr,
            .pName = "main",
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = frag_data.len,
            .pCode = frag_data.ptr,
            .pName = "main",
        },
    };
    var shaders: [2]c.VkShaderEXT = undefined;
    try check(c.vkCreateShadersEXT.?(device.handle, 2, shader_create_info, null, &shaders));

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .vma = vma,
        .swapchain = swapchain,
        .draw_image = draw_image,
        .depth_image = depth_image,
        .shaders = shaders,
    };
}

pub fn deinit(self: *@This()) void {
    _ = self;
}

pub fn update(self: *@This()) !void {
    var image_index: u32 = undefined;
    var current_frame = &self.swapchain.frames[self.swapchain.current_frame_inflight % self.swapchain.frames.len];
    try check(c.vkWaitForFences.?(self.device.handle, 1, &current_frame.render_fence, 1, 1000000000));
    // std.debug.print("------------ {d} \n", .{image_index});
    const aquire_result = c.vkAcquireNextImageKHR.?(
        self.device.handle,
        self.swapchain.swapchain,
        1000000000,
        current_frame.swapchain_semaphore,
        null,
        &image_index,
    );
    // std.debug.print("Acquire result={d} image_index={d}\n", .{ aquire_result, image_index });
    switch (aquire_result) {
        c.VK_ERROR_OUT_OF_DATE_KHR,
        c.VK_SUBOPTIMAL_KHR,
        => return,
        c.VK_TIMEOUT, c.VK_NOT_READY => return,
        else => {},
    }
    try check(c.vkResetFences.?(self.device.handle, 1, &current_frame.render_fence));
    const render_semaphore: c.VkSemaphore = self.swapchain.render_semaphores[image_index];
    // try current_frame.descriptor.clearPools(self.device);
    // current_frame.gpu_scene.deinit(self.vma.handle);

    const cmd_buffer = current_frame.command_buffer;
    try check(c.vkResetCommandBuffer.?(cmd_buffer, 0));
    var cmd_begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(c.vkBeginCommandBuffer.?(cmd_buffer, &cmd_begin_info));

    //TODO: RENDERING!
    try render(self, cmd_buffer);

    var swapchain_image_barrier: Image.Barrier = .init(cmd_buffer, self.swapchain.vk_images[image_index], c.VK_IMAGE_ASPECT_COLOR_BIT);
    swapchain_image_barrier.transition(c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_ACCESS_TRANSFER_WRITE_BIT);
    self.draw_image.copyOntoImage(
        cmd_buffer,
        .{ .vk_image = self.swapchain.vk_images[image_index], .extent = self.swapchain.extent },
    );

    swapchain_image_barrier.transition(c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0);
    try check(c.vkEndCommandBuffer.?(cmd_buffer));

    var submit_info: c.VkSubmitInfo2 = .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &.{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_frame.swapchain_semaphore,
            .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
            .value = 0,
        },
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &.{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = render_semaphore,
            .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .value = 0,
        },
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &.{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = cmd_buffer,
        },
    };

    try check(c.vkQueueSubmit2.?(self.device.graphics_queue, 1, &submit_info, current_frame.render_fence));

    var present_info: c.VkPresentInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.swapchain.swapchain,
        .swapchainCount = 1,
        .pWaitSemaphores = &render_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };

    const present_result = c.vkQueuePresentKHR.?(self.device.graphics_queue, &present_info);

    if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or present_result == c.VK_SUBOPTIMAL_KHR) {
        return;
        // self.swapchain.recreate(self.physical_device, self.device, self.surface, )
    }
    self.swapchain.current_frame_inflight += 1;
}

pub fn render(self: *@This(), cmd: c.VkCommandBuffer) !void {
    var draw_image_barrier: Image.Barrier = .init(cmd, self.draw_image.vk_image, c.VK_IMAGE_ASPECT_COLOR_BIT);

    draw_image_barrier.transition(
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    );
    var depth_image_barrier: Image.Barrier = .init(cmd, self.depth_image.vk_image, c.VK_IMAGE_ASPECT_DEPTH_BIT);
    depth_image_barrier.transition(
        c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    );
    var color_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .pNext = null,
        .imageView = self.draw_image.vk_imageview,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .color = .{
                .float32 = .{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
    };
    var depth_attachment: c.VkRenderingAttachmentInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.vk_imageview,
        .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .depthStencil = .{
                .depth = 1,
                .stencil = 0,
            },
        },
    };

    const stages = [_]c.VkShaderStageFlagBits{
        c.VK_SHADER_STAGE_VERTEX_BIT,
        c.VK_SHADER_STAGE_FRAGMENT_BIT,
    };

    const bound = [_]c.VkShaderEXT{ self.shaders[0], self.shaders[1] };

    const viewport: c.VkViewport = .{
        .width = @floatFromInt(self.draw_image.extent.width),
        .height = @floatFromInt(self.draw_image.extent.height),
        .maxDepth = 1,
    };
    const scissor: c.VkRect2D = .{
        .extent = .{
            .width = self.draw_image.extent.width,
            .height = self.draw_image.extent.height,
        },
    };
    c.vkCmdBindShadersEXT.?(cmd, 2, &stages, &bound);

    c.vkCmdSetStencilTestEnable.?(cmd, c.VK_FALSE);

    c.vkCmdSetStencilOp.?(cmd, c.VK_STENCIL_FACE_FRONT_AND_BACK, c.VK_STENCIL_OP_KEEP, c.VK_STENCIL_OP_KEEP, c.VK_STENCIL_OP_KEEP, c.VK_COMPARE_OP_ALWAYS);

    c.vkCmdSetStencilCompareMask.?(cmd, c.VK_STENCIL_FACE_FRONT_AND_BACK, 0xFF);
    c.vkCmdSetStencilWriteMask.?(cmd, c.VK_STENCIL_FACE_FRONT_AND_BACK, 0x00);
    c.vkCmdSetStencilReference.?(cmd, c.VK_STENCIL_FACE_FRONT_AND_BACK, 0);

    c.vkCmdSetViewport.?(cmd, 0, 1, &viewport);
    c.vkCmdSetScissor.?(cmd, 0, 1, &scissor);
    c.vkCmdSetRasterizerDiscardEnable.?(cmd, c.VK_FALSE); // if you use EXT_extended_dynamic_state3
    c.vkCmdSetCullMode.?(cmd, c.VK_CULL_MODE_BACK_BIT);
    c.vkCmdSetFrontFace.?(cmd, c.VK_FRONT_FACE_CLOCKWISE);
    // Depth bias: explicitly OFF
    c.vkCmdSetDepthBiasEnable.?(cmd, c.VK_FALSE);
    // (If you ever enable it, also set the parameters)
    c.vkCmdSetDepthBias.?(cmd, 0, 0, 0);

    c.vkCmdSetPolygonModeEXT.?(cmd, c.VK_POLYGON_MODE_FILL); // if supported

    c.vkCmdSetRasterizationSamplesEXT.?(cmd, c.VK_SAMPLE_COUNT_1_BIT);

    c.vkCmdSetDepthTestEnable.?(cmd, c.VK_FALSE);
    c.vkCmdSetDepthWriteEnable.?(cmd, c.VK_FALSE);
    c.vkCmdSetDepthCompareOp.?(cmd, c.VK_COMPARE_OP_ALWAYS);
    c.vkCmdSetPrimitiveTopology.?(cmd, c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);

    var render_info: c.VkRenderingInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .pNext = null,
        .flags = 0,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{
                .height = self.draw_image.extent.height,
                .width = self.draw_image.extent.width,
            },
        },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = &depth_attachment,
        .pStencilAttachment = null,
    };

    c.vkCmdBeginRendering.?(cmd, &render_info);

    c.vkCmdDraw.?(cmd, 3, 1, 0, 0);
    c.vkCmdEndRendering.?(cmd);

    draw_image_barrier.transition(c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_ACCESS_TRANSFER_READ_BIT);
}

pub fn reCreateSwapchain(self: *@This(), allocator: std.mem.Allocator, width: usize, height: usize) !void {
    try self.swapchain.recreate(
        allocator,
        self.physical_device,
        self.device,
        self.surface,
        @intCast(width),
        @intCast(height),
    );

    const scaled_height: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.extent.height)));
    const scaled_width: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.extent.width)));
    self.draw_image.extent.height = @intFromFloat(scaled_height);
    self.draw_image.extent.width = @intFromFloat(scaled_width);
}
