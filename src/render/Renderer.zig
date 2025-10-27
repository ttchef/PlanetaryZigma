const std = @import("std");
const nz = @import("numz");
pub const vk = @import("vulkan/vulkan.zig");

instance: vk.Instance,
debug_messenger: vk.DebugMessenger,
surface: vk.Surface,
physical_device: vk.PhysicalDevice,
device: vk.Device,
swapchain: vk.Swapchain,
command_pool: vk.CommandPool,

descriptor: vk.Descriptor,
descriptor_graphics: vk.Descriptor,

pipelines: [16]vk.Pipeline,
max_pipelines: usize = 0,
current_pipeline: usize = 0,

vulkan_mem_alloc: vk.Vma,
draw_image: vk.Image,

pub const Config = struct { instance: struct {
    extensions: ?[]const [*:0]const u8 = null,
    layers: ?[]const [*:0]const u8 = null,
    debug_config: vk.DebugMessenger.Config = .{},
} = .{}, device: struct {
    extensions: ?[]const [*:0]const u8 = null,
} = .{}, surface: struct {
    data: ?*anyopaque = null,
    init: ?*const fn (vk.Instance, *anyopaque) anyerror!*anyopaque = null,
} = .{}, swapchain: struct {
    width: u32 = 0,
    heigth: u32 = 0,
} };

pub fn init(config: Config) !@This() {
    const instance: vk.Instance = try .init(config.instance.extensions, config.instance.layers);
    const debug_messenger: vk.DebugMessenger = try .init(instance, config.instance.debug_config);
    const surface: vk.Surface = if (config.surface.init != null and config.surface.data != null) .{ .handle = @ptrCast(try config.surface.init.?(instance, config.surface.data.?)) } else try vk.Surface.init(instance);
    const physical_device: vk.PhysicalDevice = try .find(instance, surface);
    const device: vk.Device = try .init(physical_device, config.device.extensions);
    const command_pool: vk.CommandPool = try .init(device, physical_device.queue_family_index);
    const swapchain: vk.Swapchain = try .init(physical_device, device, command_pool, surface, config.swapchain.width, config.swapchain.heigth);

    // TODO
    //GRAPHICS pipeline

    const vulkan_mem_alloc: vk.Vma = try .init(instance, physical_device, device);
    const draw_image: vk.Image = try .init(vulkan_mem_alloc.vulkan_mem_alloc, device, swapchain.format, swapchain.extent);

    // //TODO: DONT PASS IMAGE TO DESCRIPTOR
    const descriptor: vk.Descriptor = try .init(device, draw_image.image_view);
    const descriptor_graphics: vk.Descriptor = try .init(device, draw_image.image_view);

    const shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient.comp.spv");
    const gradient_color: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient_color.comp.spv");

    var pipelines: [16]vk.Pipeline = undefined;
    var config_comp1: vk.Pipeline.Compute.Config = .{
        .descriptor_set_layouts = &.{descriptor._drawImageDescriptorLayou},
        .shader = .{
            .module = shader,
        },
    };
    pipelines[0] = try .initCompute(device, &config_comp1);
    pipelines[0].compute.data.data1 = .{ 1, 0, 0, 1 };
    pipelines[0].compute.data.data2 = .{ 0, 0, 1, 1 };

    var config_comp2: vk.Pipeline.Compute.Config = .{
        .descriptor_set_layouts = &.{descriptor._drawImageDescriptorLayou},
        .shader = .{
            .module = gradient_color,
        },
    };
    pipelines[1] = try .initCompute(device, &config_comp2);
    pipelines[1].compute.data.data2 = .{ 0.1, 0.2, 0.4, 0.97 };

    vk.c.vkDestroyShaderModule(device.handle, shader, null);
    vk.c.vkDestroyShaderModule(device.handle, gradient_color, null);

    //TODO GET GRAPHICS PIPELINE WORKING
    const frag: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle.frag.spv");
    const vert: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle.vert.spv");

    var color_blend: vk.c.VkPipelineColorBlendAttachmentState = .{
        .colorWriteMask = vk.c.VK_COLOR_COMPONENT_R_BIT | vk.c.VK_COLOR_COMPONENT_G_BIT | vk.c.VK_COLOR_COMPONENT_B_BIT | vk.c.VK_COLOR_COMPONENT_A_BIT,
    };
    var state: []const vk.c.VkDynamicState = &.{ vk.c.VK_DYNAMIC_STATE_VIEWPORT, vk.c.VK_DYNAMIC_STATE_SCISSOR };
    var config_graphics: vk.Pipeline.Graphics.Config = .{
        .vertex_shaders = .{
            .module = vert,
        },
        .fragment_shaders = .{
            .module = frag,
        },
        .geometry_shader = null,
        .descriptor_set_layouts = &.{descriptor_graphics._drawImageDescriptorLayou},
    };
    config_graphics.viewport_state.scissorCount = 1;
    config_graphics.viewport_state.viewportCount = 1;
    config_graphics.color_blend_state.attachmentCount = 1;
    config_graphics.color_blend_state.logicOp = vk.c.VK_LOGIC_OP_COPY;
    config_graphics.color_blend_state.pAttachments = &color_blend;
    config_graphics.dynamic_state.dynamicStateCount = 2;
    config_graphics.dynamic_state.pDynamicStates = &state[0];
    config_graphics.render_info.colorAttachmentCount = 1;
    config_graphics.render_info.pColorAttachmentFormats = &draw_image.format;
    config_graphics.render_info.depthAttachmentFormat = vk.c.VK_FORMAT_UNDEFINED;
    pipelines[2] = try .initGraphics(device, &config_graphics);

    std.debug.print("Address {*}\n", .{instance.handle});
    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .command_pool = command_pool,
        .descriptor = descriptor,
        .pipelines = pipelines,
        .current_pipeline = 0,
        .max_pipelines = 2,
        .vulkan_mem_alloc = vulkan_mem_alloc,
        .draw_image = draw_image,
        .descriptor_graphics = descriptor_graphics,
    };
}

pub fn draw(self: *@This(), time: f32) !void {
    var image_index: u32 = undefined;
    const current_frame = self.swapchain.frames[self.swapchain.current_frame_inflight % self.swapchain.frames.len];
    try vk.check(vk.c.vkWaitForFences(self.device.handle, 1, &current_frame.render_fence, 1, 1000000000));
    try vk.check(vk.c.vkResetFences(self.device.handle, 1, &current_frame.render_fence));
    try vk.check(vk.c.vkAcquireNextImageKHR(
        self.device.handle,
        self.swapchain.swapchain,
        1000000000,
        current_frame.swapchain_semaphore,
        null,
        &image_index,
    ));

    const cmd_buffer = current_frame.command_buffer;
    try vk.check(vk.c.vkResetCommandBuffer(cmd_buffer, 0));
    var cmd_begin_info: vk.c.VkCommandBufferBeginInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.check(vk.c.vkBeginCommandBuffer(cmd_buffer, &cmd_begin_info));

    try vk.imageMemBarrier(cmd_buffer, self.draw_image.image, self.draw_image.format, vk.c.VK_IMAGE_LAYOUT_UNDEFINED, vk.c.VK_IMAGE_LAYOUT_GENERAL);

    self.current_pipeline = @mod(@as(usize, @intFromFloat(time)), 2);
    std.debug.print("time converted {d} time {d}\r", .{ self.current_pipeline, time });

    const pipeline: vk.Pipeline = self.pipelines[self.current_pipeline];

    vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.get().handle);
    vk.c.vkCmdBindDescriptorSets(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.get().layout, 0, 1, &self.descriptor._drawImageDescriptors, 0, null);

    vk.c.vkCmdPushConstants(cmd_buffer, pipeline.get().layout, vk.c.VK_SHADER_STAGE_COMPUTE_BIT, 0, @sizeOf(vk.Pipeline.Compute.PushConstant), &pipeline.compute.data);

    vk.c.vkCmdDispatch(
        cmd_buffer,
        @intFromFloat(@ceil(@as(f32, @floatFromInt(self.swapchain.extent.width)) / 16)),
        @intFromFloat(@ceil(@as(f32, @floatFromInt(self.swapchain.extent.height)) / 16)),
        1,
    );

    try vk.imageMemBarrier(cmd_buffer, self.draw_image.image, self.draw_image.format, vk.c.VK_IMAGE_LAYOUT_GENERAL, vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL);
    draw_geometry(cmd_buffer, self.pipelines[2], self.draw_image);
    try vk.imageMemBarrier(cmd_buffer, self.draw_image.image, self.draw_image.format, vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    try vk.imageMemBarrier(cmd_buffer, self.swapchain.vk_images[image_index], self.draw_image.format, vk.c.VK_IMAGE_LAYOUT_UNDEFINED, vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    // try vk.imageMemBarrier(cmd_buffer, self.draw_image.image, self.draw_image.format, vk.c.VK_IMAGE_LAYOUT_GENERAL, vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    // try vk.imageMemBarrier(cmd_buffer, self.swapchain.vk_images[image_index], self.swapchain.format, vk.c.VK_IMAGE_LAYOUT_UNDEFINED, vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    vk.copyImageToImage(
        cmd_buffer,
        self.draw_image.image,
        self.swapchain.vk_images[image_index],
        self.draw_image.image_extent,
        self.swapchain.extent,
    );

    try vk.imageMemBarrier(cmd_buffer, self.swapchain.vk_images[image_index], self.swapchain.format, vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    try vk.check(vk.c.vkEndCommandBuffer(cmd_buffer));

    var submit_info: vk.c.VkSubmitInfo2 = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .waitSemaphoreInfoCount = 1,
        .pWaitSemaphoreInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_frame.swapchain_semaphore,
            .stageMask = vk.c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR,
            .value = 1,
        },
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = current_frame.render_done_semaphore,
            .stageMask = vk.c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .value = 1,
        },
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = cmd_buffer,
        },
    };

    try vk.check(vk.c.vkQueueSubmit2(self.device.getQueue(self.physical_device.queue_family_index), 1, &submit_info, current_frame.render_fence));

    var present_info: vk.c.VkPresentInfoKHR = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.swapchain.swapchain,
        .swapchainCount = 1,
        .pWaitSemaphores = &current_frame.render_done_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };

    try vk.check(vk.c.vkQueuePresentKHR(self.device.getQueue(self.physical_device.queue_family_index), &present_info));

    self.swapchain.current_frame_inflight += 1;
}

pub fn deinit(self: @This()) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.handle);
    self.swapchain.deinit(self.device, self.command_pool);
    self.command_pool.deinit(self.device);

    self.descriptor.deinit(self.device);
    for (0..self.max_pipelines) |i|
        self.pipelines[i].deinit(self.device);
    self.draw_image.deinit(self.vulkan_mem_alloc, self.device);
    self.vulkan_mem_alloc.deinit();

    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
}

fn draw_geometry(cmd: vk.c.VkCommandBuffer, pipeline: vk.Pipeline, draw_image: vk.Image) void {
    var color_attachment: vk.c.VkRenderingAttachmentInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .pNext = null,
        .imageView = draw_image.image_view,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = vk.c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = vk.c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = vk.c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
    };

    var renderInfo: vk.c.VkRenderingInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .pNext = null,
        .flags = 0,
        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = .{
                .height = draw_image.image_extent.height,
                .width = draw_image.image_extent.width,
            },
        },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    vk.c.vkCmdBeginRendering(cmd, &renderInfo);

    vk.c.vkCmdBindPipeline(cmd, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline.get().handle);

    var viewport: vk.c.VkViewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(draw_image.image_extent.width),
        .height = @floatFromInt(draw_image.image_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };

    vk.c.vkCmdSetViewport(cmd, 0, 1, &viewport);

    var scissor: vk.c.VkRect2D = .{
        .offset = .{
            .x = 0,
            .y = 0,
        },
        .extent = .{
            .width = draw_image.image_extent.width,
            .height = draw_image.image_extent.height,
        },
    };

    vk.c.vkCmdSetScissor(cmd, 0, 1, &scissor);

    vk.c.vkCmdDraw(cmd, 3, 1, 0, 0);

    vk.c.vkCmdEndRendering(cmd);
}
