const std = @import("std");
const nz = @import("numz");
pub const vk = @import("vulkan/vulkan.zig");
const Obj = @import("asset/Obj.zig");
const tiny_obj = @import("tiny_obj_loader");

pub var rect_vertices = [_]vk.Mesh.Vertex{
    .{
        .position = .{ 0.5, -0.5, 0.0, 1.0 },
    },
    .{
        .position = .{ 0.5, 0.5, 0.0, 1.0 },
    },
    .{
        .position = .{ -1, -0.5, 0.0, 1.0 },
    },
    .{
        .position = .{ -0.5, 0.5, 0.0, 1.0 },
    },
};

pub var rect_indices = [_]u32{
    0, 1, 2,
    2, 1, 3,
};

instance: vk.Instance,
debug_messenger: vk.DebugMessenger,
surface: vk.Surface,
physical_device: vk.PhysicalDevice,
device: vk.Device,
swapchain: vk.Swapchain,

descriptor: vk.Descriptor,
descriptor_graphics: vk.Descriptor,

pipelines: [16]vk.Pipeline,
max_pipelines: usize = 0,
current_pipeline: usize = 0,
the_mesh: vk.Mesh,
meshes: std.ArrayList(vk.Mesh) = .empty,

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
    const swapchain: vk.Swapchain = try .init(physical_device, device, surface, config.swapchain.width, config.swapchain.heigth);
    const vulkan_mem_alloc: vk.Vma = try .init(instance, physical_device, device);
    const draw_image: vk.Image = try .init(vulkan_mem_alloc.handle, device, swapchain.format, swapchain.extent);

    // //TODO: DONT PASS IMAGE TO DESCRIPTOR
    const descriptor: vk.Descriptor = try .init(device, draw_image.image_view);
    const descriptor_graphics: vk.Descriptor = try .init(device, draw_image.image_view);

    const the_mesh: vk.Mesh = try .init(device, vulkan_mem_alloc.handle, @ptrCast(&rect_indices), @ptrCast(&rect_vertices));

    const shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient.comp.spv");
    const gradient_color: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient_color.comp.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, shader, null);
    defer vk.c.vkDestroyShaderModule(device.handle, gradient_color, null);

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

    //TODO GET GRAPHICS PIPELINE WORKING
    const frag: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle.frag.spv");
    const vert: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle.vert.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, vert, null);
    defer vk.c.vkDestroyShaderModule(device.handle, frag, null);

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
        .descriptor_set_layouts = &.{descriptor_graphics._drawImageDescriptorLayou},
        .push_constants = &.{},
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

    const mesh_vert: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle_mesh.vert.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, mesh_vert, null);
    var config_mesh: vk.Pipeline.Graphics.Config = .{
        .fragment_shaders = .{
            .module = frag,
        },
        .vertex_shaders = .{
            .module = mesh_vert,
        },
        .descriptor_set_layouts = &.{descriptor_graphics._drawImageDescriptorLayou},
        .push_constants = &.{.{
            .offset = 0,
            .size = @sizeOf(vk.Mesh.GPUDrawPushConstants),
            .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
        }},
    };
    config_mesh.viewport_state.scissorCount = 1;
    config_mesh.viewport_state.viewportCount = 1;
    config_mesh.color_blend_state.attachmentCount = 1;
    config_mesh.color_blend_state.logicOp = vk.c.VK_LOGIC_OP_COPY;
    config_mesh.color_blend_state.pAttachments = &color_blend;
    config_mesh.dynamic_state.dynamicStateCount = 2;
    config_mesh.dynamic_state.pDynamicStates = &state[0];
    config_mesh.render_info.colorAttachmentCount = 1;
    config_mesh.render_info.pColorAttachmentFormats = &draw_image.format;
    config_mesh.render_info.depthAttachmentFormat = vk.c.VK_FORMAT_UNDEFINED;
    config_mesh.rasterization_state.cullMode = vk.c.VK_CULL_MODE_NONE;
    pipelines[3] = try .initGraphics(device, &config_mesh);

    std.debug.print("Address {*}\n", .{instance.handle});

    return .{
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .descriptor = descriptor,
        .pipelines = pipelines,
        .current_pipeline = 0,
        .max_pipelines = 4,
        .vulkan_mem_alloc = vulkan_mem_alloc,
        .the_mesh = the_mesh,
        .draw_image = draw_image,
        .descriptor_graphics = descriptor_graphics,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.handle);
    self.swapchain.deinit(self.device);

    self.descriptor.deinit(self.device);
    self.descriptor_graphics.deinit(self.device);
    for (0..self.max_pipelines) |i|
        self.pipelines[i].deinit(self.device);
    self.draw_image.deinit(self.vulkan_mem_alloc, self.device);

    self.the_mesh.deinit(self.vulkan_mem_alloc.handle);
    for (self.meshes.items) |mesh| {
        mesh.deinit(self.vulkan_mem_alloc.handle);
    }
    self.meshes.deinit(allocator);

    self.vulkan_mem_alloc.deinit();

    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
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

    var draw_image_barrier: vk.Barrier = .init(cmd_buffer, self.draw_image.image);
    draw_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_GENERAL, vk.c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, vk.c.VK_ACCESS_SHADER_WRITE_BIT);

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

    draw_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT, vk.c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);

    //START DRAWING VERTECIES
    var color_attachment: vk.c.VkRenderingAttachmentInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .pNext = null,
        .imageView = self.draw_image.image_view,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = vk.c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = vk.c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = vk.c.VK_ATTACHMENT_LOAD_OP_LOAD,
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
                .height = self.draw_image.image_extent.height,
                .width = self.draw_image.image_extent.width,
            },
        },
        .layerCount = 1,
        .viewMask = 0,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment,
        .pDepthAttachment = null,
        .pStencilAttachment = null,
    };

    vk.c.vkCmdBeginRendering(cmd_buffer, &renderInfo);

    vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[2].get().handle);

    var viewport: vk.c.VkViewport = .{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.draw_image.image_extent.width),
        .height = @floatFromInt(self.draw_image.image_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };

    vk.c.vkCmdSetViewport(cmd_buffer, 0, 1, &viewport);

    var scissor: vk.c.VkRect2D = .{
        .offset = .{
            .x = 0,
            .y = 0,
        },
        .extent = .{
            .width = self.draw_image.image_extent.width,
            .height = self.draw_image.image_extent.height,
        },
    };

    vk.c.vkCmdSetScissor(cmd_buffer, 0, 1, &scissor);

    //Triangle
    vk.c.vkCmdDraw(cmd_buffer, 3, 1, 0, 0);

    //The mesh
    vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[3].get().handle);

    //projection matrix + view + model
    const view: nz.Mat4x4(f32) = .translate(.{ 0, 0, -5 });
    var projection: nz.Mat4x4(f32) = .perspective(
        70,
        @floatFromInt(self.draw_image.image_extent.width / self.draw_image.image_extent.height),
        10000,
        0.1,
    );
    projection.d[6] *= -1;

    var push: vk.Mesh.GPUDrawPushConstants = .{
        .vertex_buffer = self.meshes.items[0].vertex_buffer_address,
        .world_matrix = projection.mul(view).d,
    };

    vk.c.vkCmdPushConstants(
        cmd_buffer,
        self.pipelines[3].get().layout,
        vk.c.VK_SHADER_STAGE_VERTEX_BIT,
        0,
        @sizeOf(vk.Mesh.GPUDrawPushConstants),
        &push,
    );
    vk.c.vkCmdBindIndexBuffer(cmd_buffer, self.meshes.items[0].index_buffer.buffer, 0, vk.c.VK_INDEX_TYPE_UINT32);
    vk.c.vkCmdDrawIndexed(cmd_buffer, self.meshes.items[0].indecies_count, 1, 0, 0, 0);

    vk.c.vkCmdEndRendering(cmd_buffer);
    //DONE RENDERING VERTECIES

    draw_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, vk.c.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.c.VK_ACCESS_TRANSFER_READ_BIT);

    var swapchain_image_barrier: vk.Barrier = .init(cmd_buffer, self.swapchain.vk_images[image_index]);
    swapchain_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.c.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.c.VK_ACCESS_TRANSFER_WRITE_BIT);
    vk.copyImageToImage(
        cmd_buffer,
        self.draw_image.image,
        self.swapchain.vk_images[image_index],
        self.draw_image.image_extent,
        self.swapchain.extent,
    );
    swapchain_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, vk.c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0);
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

    try vk.check(vk.c.vkQueueSubmit2(self.device.graphics_queue, 1, &submit_info, current_frame.render_fence));

    var present_info: vk.c.VkPresentInfoKHR = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pSwapchains = &self.swapchain.swapchain,
        .swapchainCount = 1,
        .pWaitSemaphores = &current_frame.render_done_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };

    try vk.check(vk.c.vkQueuePresentKHR(self.device.graphics_queue, &present_info));

    self.swapchain.current_frame_inflight += 1;
}

//TODO: Fix vertcies and indecies + allocation failure.
//TODO: move logic away
pub fn uploadMeshToGPU(self: *@This(), allocator: std.mem.Allocator, path: []const u8) !void {
    std.debug.print("\nTRY TO ADD MESH {s}\n\n", .{path});

    var attribs = tiny_obj.tinyobj_attrib_t{};
    var shapes: [*c]tiny_obj.tinyobj_shape_t = null;
    var num_shapes: usize = 0;
    var materials: [*c]tiny_obj.tinyobj_material_t = null;
    var num_materials: usize = 0;

    std.debug.print("DEBUG: About to call tinyobj_parse_obj\n", .{});

    const result = tiny_obj.tinyobj_parse_obj(
        &attribs,
        &shapes,
        &num_shapes,
        &materials,
        &num_materials,
        path.ptr,
        Obj.tinyObjFileReader,
        null,
        tiny_obj.TINYOBJ_FLAG_TRIANGULATE,
    );

    std.debug.print("DEBUG: tinyobj_parse_obj returned {d}\n", .{result});

    if (result != tiny_obj.TINYOBJ_SUCCESS) {
        std.debug.print("Failed to parse OBJ file: {s}, error code: {d}\n", .{ path, result });
        return error.ObjParseFailed;
    }

    var vertices_list: std.ArrayList(vk.Mesh.Vertex) = .empty;
    var indecies_list: std.ArrayList(u32) = .empty;
    defer vertices_list.deinit(allocator);
    defer indecies_list.deinit(allocator);

    // Process all faces from the attributes
    var face_offset: usize = 0;
    var face_idx: usize = 0;
    while (face_idx < @as(usize, @intCast(attribs.num_faces))) : (face_idx += 1) {
        const face_vertex_count = attribs.face_num_verts[face_idx];

        // For triangulated meshes, we get triangles (3 vertices per face)
        if (face_vertex_count == 3) {
            var i: usize = 0;
            while (i < 3) : (i += 1) {
                const index = attribs.faces[face_offset + i];

                // Get vertex position
                const pos_x = attribs.vertices[@as(usize, @intCast(3 * index.v_idx))];
                const pos_y = attribs.vertices[@as(usize, @intCast(3 * index.v_idx + 1))];
                const pos_z = attribs.vertices[@as(usize, @intCast(3 * index.v_idx + 2))];

                const vertex: vk.Mesh.Vertex = .{
                    .position = .{ pos_x, pos_y, pos_z, 1.0 },
                };

                try vertices_list.append(allocator, vertex);
                try indecies_list.append(allocator, @intCast(indecies_list.items.len));

                std.debug.print("index: {d}, vertex: {any}\n", .{ index.v_idx, vertex });
            }
        }

        face_offset += @as(usize, @intCast(face_vertex_count));
    }

    // Free tiny_obj_loader memory
    tiny_obj.tinyobj_attrib_free(&attribs);
    tiny_obj.tinyobj_shapes_free(shapes, num_shapes);
    tiny_obj.tinyobj_materials_free(materials, num_materials);

    if (vertices_list.items.len > 0 and indecies_list.items.len > 0) {
        std.debug.print("\nADDED MESH {s}\n\n", .{path});

        try self.meshes.append(allocator, try .init(
            self.device,
            self.vulkan_mem_alloc.handle,
            indecies_list.items,
            vertices_list.items,
        ));
    } else {
        std.debug.print("\nNo valid mesh data found in {s}\n\n", .{path});
    }
}
