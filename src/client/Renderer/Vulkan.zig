const std = @import("std");
const AssetServer = @import("shared").AssetServer;
pub const c = @import("vulkan");
const shaderc = @import("shaderc");
const Instance = @import("Vulkan/Instance.zig");
const DebugMessenger = @import("Vulkan/DebugMessenger.zig");
const PhysicalDevice = @import("Vulkan/device.zig").Physical;
const Device = @import("Vulkan/device.zig").Logical;
const Vma = @import("Vulkan/Vma.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");
const Surface = @import("Vulkan/Surface.zig");
const Image = @import("Vulkan/Image.zig");
const descriptor = @import("Vulkan/desrciptor.zig");
pub const check = @import("Vulkan/utils.zig").check;
const ext = @import("Vulkan/ExtensionFunctions.zig");

instance: Instance,
debug_messenger: DebugMessenger,
surface: Surface,
physical_device: PhysicalDevice,
device: Device,
vma: Vma,
swapchain: Swapchain,
draw_image: Image,
depth_image: Image,

//Temporary
shaders: [2]c.VkShaderEXT,
layout: descriptor.Layout,
elapsed_time: f32 = 0,

// const vertex_array = [_]Vertex.{
//     .{
//         .position = .{0,-0.5,0,0},
//         .color = .{1,0,0,1}.
//     },
//     .{
//         .position = .{0.5,0.5,0,0},
//         .color = .{1,0,0,1}.
//     },
//
//     .{
//         .position = .{-0.5,0.5,0,0},
//         .color = .{1,0,0,1}.
//     },
// };
const Vertex = extern struct {
    position: [4]f32,
    color: [4]f32,
    uv: [4]f32,
};

pub const InitOptions = struct {
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

pub fn init(allocator: std.mem.Allocator, asset_server: *AssetServer, options: InitOptions) !*@This() {
    const self = try allocator.create(@This());
    self.instance = try .init(allocator, options.instance.extensions, options.instance.layers);
    ext.loadInstanceFunctions(self.instance.handle);
    self.debug_messenger = try .init(self.instance, .{
        .severities = if (try std.process.Environ.contains(.empty, allocator, "RENDERDOC_CAPFILE")) .{} else .{
            .warning = true,
            .verbose = true,
            .@"error" = true,
            .info = true,
        },
    });
    self.surface = if (options.surface.init != null and options.surface.data != null) .{
        .handle = @ptrCast(try options.surface.init.?(self.instance.handle, options.surface.data.?)),
    } else return error.configSurface;
    self.physical_device = try .pick(self.instance, self.surface.handle);
    self.device = try .init(self.physical_device, options.device.extensions);
    ext.loadDeviceFunctions(self.device.handle);
    self.vma = try .init(self.instance, self.physical_device, self.device);
    self.swapchain = try .init(allocator, self.vma, self.physical_device, self.device, self.surface, options.swapchain.width, options.swapchain.heigth);
    self.draw_image = try .init(
        self.vma.handle,
        self.device,
        c.VK_FORMAT_R16G16B16A16_SFLOAT,
        self.swapchain.extent,
        c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    self.depth_image = try .init(
        self.vma.handle,
        self.device,
        c.VK_FORMAT_D32_SFLOAT,
        self.swapchain.extent,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        false,
    );

    // const layout: descriptor.Layout = try .init(self.device, &.{.{
    //     .binding = 0,
    //     .descriptorCount = 1,
    //     .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    //     .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
    // }});

    try asset_server.loadAsset(@This(), self, "shaders/vertex.vert", loadShader);
    try asset_server.loadAsset(@This(), self, "shaders/fragment.frag", loadShader);

    // self.shaders = .{ null, null };
    self.layout = undefined;
    self.elapsed_time = 0;
    return self;
}

fn loadShader(user_data: *anyopaque, path: []const u8, io: std.Io, allocator: std.mem.Allocator, file: std.Io.File) !void {
    const self: *@This() = @ptrCast(@alignCast(user_data));
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const content = try reader.interface.allocRemaining(allocator, .unlimited);
    std.debug.print("size:  {d}\n", .{content.len});
    defer allocator.free(content);

    const compiler = shaderc.shaderc_compiler_initialize();
    defer shaderc.shaderc_compiler_release(compiler);

    if (std.mem.eql(u8, path, "shaders/vertex.vert")) {
        const result = shaderc.shaderc_compile_into_spv(
            compiler,
            content.ptr,
            content.len,
            shaderc.shaderc_glsl_vertex_shader,
            "vertex.vert",
            "main",
            null,
        );
        defer shaderc.shaderc_result_release(result);
        const status = shaderc.shaderc_result_get_compilation_status(result);
        std.debug.print("result code {d}\n", .{status});
        if (status != shaderc.shaderc_compilation_status_success) {
            std.debug.print("err message {s}\n", .{shaderc.shaderc_result_get_error_message(result)});
        }
        const data = shaderc.shaderc_result_get_bytes(result);
        const len = shaderc.shaderc_result_get_length(result);
        // std.debug.print("size:  {d}\n", .{len});
        // std.debug.print("data:  {s}\n", .{data});

        const shader_create_info = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .nextStage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = len,
            .pCode = data,
            .pName = "main",
        };

        try check(ext.vkCreateShadersEXT(self.device.handle, 1, &shader_create_info, null, &self.shaders[0]));
    } else if (std.mem.eql(u8, path, "shaders/fragment.frag")) {
        const result = shaderc.shaderc_compile_into_spv(
            compiler,
            content.ptr,
            content.len,
            shaderc.shaderc_glsl_fragment_shader,
            "fragment.frag",
            "main",
            null,
        );
        defer shaderc.shaderc_result_release(result);
        const data = shaderc.shaderc_result_get_bytes(result);
        const len = shaderc.shaderc_result_get_length(result);
        const shader_create_info = c.VkShaderCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_CREATE_INFO_EXT,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .codeType = c.VK_SHADER_CODE_TYPE_SPIRV_EXT,
            .codeSize = len,
            .pCode = data,
            .pName = "main",
        };

        try check(ext.vkCreateShadersEXT(self.device.handle, 1, &shader_create_info, null, &self.shaders[1]));
    }
}

pub fn deinit(self: *@This()) void {
    check(c.vkDeviceWaitIdle(self.device.handle)) catch {};

    ext.vkDestroyShaderEXT(self.device.handle, self.shaders[0], null);
    ext.vkDestroyShaderEXT(self.device.handle, self.shaders[1], null);
    self.depth_image.deinit(self.vma, self.device);
    self.draw_image.deinit(self.vma, self.device);
    self.swapchain.deinit(self.device);
    self.vma.deinit();
    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
}

pub fn update(self: *@This(), time: f32) !void {
    var image_index: u32 = undefined;
    var current_frame = &self.swapchain.frames[self.swapchain.current_frame_inflight % self.swapchain.frames.len];
    try check(c.vkWaitForFences(self.device.handle, 1, &current_frame.render_fence, 1, 1000000000));
    // std.debug.print("------------ {d} \n", .{image_index});
    const aquire_result = c.vkAcquireNextImageKHR(
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
    try check(c.vkResetFences(self.device.handle, 1, &current_frame.render_fence));
    const render_semaphore: c.VkSemaphore = self.swapchain.render_semaphores[image_index];
    // try current_frame.descriptor.clearPools(self.device);
    // current_frame.gpu_scene.deinit(self.vma.handle);

    const cmd_buffer = current_frame.command_buffer;
    try check(c.vkResetCommandBuffer(cmd_buffer, 0));
    var cmd_begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(c.vkBeginCommandBuffer(cmd_buffer, &cmd_begin_info));

    //TODO: RENDERING!
    try render(self, cmd_buffer, time);

    var swapchain_image_barrier: Image.Barrier = .init(cmd_buffer, self.swapchain.vk_images[image_index], c.VK_IMAGE_ASPECT_COLOR_BIT);
    swapchain_image_barrier.transition(c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_ACCESS_TRANSFER_WRITE_BIT);
    self.draw_image.copyOntoImage(
        cmd_buffer,
        .{ .vk_image = self.swapchain.vk_images[image_index], .extent = self.swapchain.extent },
    );

    swapchain_image_barrier.transition(c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0);
    try check(c.vkEndCommandBuffer(cmd_buffer));

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

    try check(c.vkQueueSubmit2(self.device.graphics_queue, 1, &submit_info, current_frame.render_fence));

    var present_info: c.VkPresentInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.swapchain.swapchain,
        .swapchainCount = 1,
        .pWaitSemaphores = &render_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };

    const present_result = c.vkQueuePresentKHR(self.device.graphics_queue, &present_info);

    if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or present_result == c.VK_SUBOPTIMAL_KHR) {
        return;
        // self.swapchain.recreate(self.physical_device, self.device, self.surface, )
    }
    self.swapchain.current_frame_inflight += 1;
}

pub fn render(self: *@This(), cmd: c.VkCommandBuffer, time: f32) !void {
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
        c.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        c.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        c.VK_SHADER_STAGE_GEOMETRY_BIT,
    };

    const bound = [_]c.VkShaderEXT{ self.shaders[0], self.shaders[1], null, null, null };

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
    ext.vkCmdBindShadersEXT(cmd, stages.len, &stages[0], &bound[0]);

    ext.vkCmdSetViewportWithCountEXT(cmd, 1, &viewport);
    ext.vkCmdSetScissorWithCountEXT(cmd, 1, &scissor);

    self.elapsed_time += time;
    // std.debug.print("time: {d}\n", .{self.elapsed_time});
    const tmp: i32 = @intFromFloat(self.elapsed_time / 100);
    // std.debug.print("fixed-time: {d}\n", .{tmp});
    if (@mod(tmp, 2) == 1) {
        ext.vkCmdSetCullModeEXT(cmd, c.VK_CULL_MODE_NONE);
    } else {
        // ext.vkCmdSetCullModeEXT(cmd, c.VK_CULL_MODE_BACK_BIT);
        ext.vkCmdSetCullModeEXT(cmd, c.VK_CULL_MODE_NONE);
    }
    ext.vkCmdSetFrontFaceEXT(cmd, c.VK_FRONT_FACE_COUNTER_CLOCKWISE);
    ext.vkCmdSetDepthTestEnableEXT(cmd, c.VK_TRUE);
    ext.vkCmdSetDepthWriteEnableEXT(cmd, c.VK_TRUE);
    ext.vkCmdSetDepthCompareOpEXT(cmd, c.VK_COMPARE_OP_LESS_OR_EQUAL);
    ext.vkCmdSetPrimitiveTopologyEXT(cmd, c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    ext.vkCmdSetRasterizerDiscardEnableEXT(cmd, c.VK_FALSE);
    ext.vkCmdSetPolygonModeEXT(cmd, c.VK_POLYGON_MODE_FILL);
    ext.vkCmdSetRasterizationSamplesEXT(cmd, c.VK_SAMPLE_COUNT_1_BIT);
    ext.vkCmdSetAlphaToCoverageEnableEXT(cmd, c.VK_TRUE);
    ext.vkCmdSetDepthBiasEnableEXT(cmd, c.VK_FALSE);
    ext.vkCmdSetStencilTestEnableEXT(cmd, c.VK_FALSE);
    ext.vkCmdSetPrimitiveRestartEnableEXT(cmd, c.VK_FALSE);

    const sample_mask: u32 = 0xFF;
    ext.vkCmdSetSampleMaskEXT(cmd, c.VK_SAMPLE_COUNT_1_BIT, &sample_mask);

    const color_blend_enables: c.VkBool32 = c.VK_FALSE;
    const color_blend_component_flags: c.VkColorComponentFlags = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    ext.vkCmdSetColorBlendEnableEXT(cmd, 0, 1, &color_blend_enables);
    ext.vkCmdSetColorWriteMaskEXT(cmd, 0, 1, &color_blend_component_flags);

    ext.vkCmdSetDepthBoundsTestEnable(cmd, c.VK_FALSE);
    ext.vkCmdSetDepthClampEnableEXT(cmd, c.VK_FALSE);
    ext.vkCmdSetAlphaToOneEnableEXT(cmd, c.VK_FALSE);
    ext.vkCmdSetLogicOpEnableEXT(cmd, c.VK_FALSE);

    const vertexInputBinding: c.VkVertexInputBindingDescription2EXT = .{
        .sType = c.VK_STRUCTURE_TYPE_VERTEX_INPUT_BINDING_DESCRIPTION_2_EXT,
        .binding = 0,
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        .stride = @sizeOf(Vertex),
        .divisor = 1,
    };
    const vertexAttributes = &[_]c.VkVertexInputAttributeDescription2EXT{
        .{
            .sType = c.VK_STRUCTURE_TYPE_VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT,
            .location = 0,
            .binding = 0,
            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = 0,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT,
            .location = 1,
            .binding = 0,
            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @sizeOf([4]f32),
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_VERTEX_INPUT_ATTRIBUTE_DESCRIPTION_2_EXT,
            .location = 2,
            .binding = 0,
            .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = 2 * @sizeOf([4]f32),
        },
    };

    ext.vkCmdSetVertexInputEXT(cmd, 1, &vertexInputBinding, 3, &vertexAttributes[0]);

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

    ext.vkCmdBeginRendering(cmd, &render_info);

    c.vkCmdDraw(cmd, 3, 1, 0, 0);
    ext.vkCmdEndRendering(cmd);

    draw_image_barrier.transition(c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_ACCESS_TRANSFER_READ_BIT);
}

pub fn resize(self: *@This(), allocator: std.mem.Allocator, width: u32, height: u32) !void {
    try self.swapchain.recreate(
        allocator,
        self.physical_device,
        self.device,
        self.surface,
        width,
        height,
    );

    const scaled_height: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.extent.height)));
    const scaled_width: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.extent.width)));
    self.draw_image.extent.height = @intFromFloat(scaled_height);
    self.draw_image.extent.width = @intFromFloat(scaled_width);
}
