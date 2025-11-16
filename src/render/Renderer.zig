const std = @import("std");
const nz = @import("numz");
pub const vk = @import("vulkan/vulkan.zig");
const Obj = @import("asset/Obj.zig");
const tiny_obj = @import("tiny_obj_loader");

//TODO: WILL REMOVE (but exist temporarly for the learnding):
const GPUSceneData = struct {
    view: nz.Mat4x4(f32),
    proj: nz.Mat4x4(f32),
    viewproj: nz.Mat4x4(f32),
    ambient_color: nz.Vec3(f32),
    sunlight_direction: nz.Vec3(f32),
    sunlight_color: nz.Vec3(f32),
};

//TODO: WILL REMOVE (but exist temporarly for the learnding):
pipelines: [16]vk.Pipeline,
max_pipelines: usize = 0,
current_pipeline: usize = 0,
meshes: std.ArrayList(vk.Mesh) = .empty,
compute_descriptor_layout: vk.descriptor.Layout,
graphics_descriptor_layout: vk.descriptor.Layout,
_singleImageDescriptorLayout: vk.descriptor.Layout,
_gpuSceneDataDescriptorLayout: vk.descriptor.Layout,
scene_data: GPUSceneData,
_whiteImage: vk.Image,
_blackImage: vk.Image,
_greyImage: vk.Image,
_errorCheckerboardImage: vk.Image,
_defaultSamplerLinear: vk.c.VkSampler,
_defaultSamplerNearest: vk.c.VkSampler,

allocator: std.mem.Allocator,
instance: vk.Instance,
debug_messenger: vk.DebugMessenger,
surface: vk.Surface,
physical_device: vk.PhysicalDevice,
device: vk.Device,
swapchain: vk.Swapchain,
vma: vk.Vma,
draw_image: vk.Image,
depth_image: vk.Image,
resize_request: bool = false,

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

pub fn init(allocator: std.mem.Allocator, config: Config) !@This() {
    const instance: vk.Instance = try .init(config.instance.extensions, config.instance.layers);
    const debug_messenger: vk.DebugMessenger = try .init(instance, config.instance.debug_config);
    const surface: vk.Surface = if (config.surface.init != null and config.surface.data != null) .{ .handle = @ptrCast(try config.surface.init.?(instance, config.surface.data.?)) } else try vk.Surface.init(instance);
    const physical_device: vk.PhysicalDevice = try .find(instance, surface);
    const device: vk.Device = try .init(physical_device, config.device.extensions);
    const swapchain: vk.Swapchain = try .init(allocator, physical_device, device, surface, config.swapchain.width, config.swapchain.heigth);
    const vma: vk.Vma = try .init(instance, physical_device, device);

    const draw_image: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R16G16B16A16_SFLOAT,
        swapchain.extent,
        vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.c.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    const depth_image: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_D32_SFLOAT,
        swapchain.extent,
        vk.c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        vk.c.VK_IMAGE_ASPECT_DEPTH_BIT,
        false,
    );

    //3 default textures, white, grey, black. 1 pixel each
    var white: u32 = nz.color.Rgba(f32).white.toU32();
    const _whiteImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try _whiteImage.uploadDataToImage(device, vma.handle, &white);

    var grey: u32 = nz.color.Rgba(f32).grey.toU32();
    const _greyImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try _greyImage.uploadDataToImage(device, vma.handle, &grey);

    var black: u32 = nz.color.Rgba(f32).black.toU32();
    const _blackImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try _blackImage.uploadDataToImage(device, vma.handle, &black);

    //checkerboard image
    const magenta: u32 = nz.color.Rgba(f32).new(1, 0, 1, 1).toU32();
    var pixels: [16 * 16]u32 = undefined;
    for (0..16) |x| {
        for (0..16) |y| {
            pixels[y * 16 + x] = if (std.math.pow(usize, @mod(x, 2), @mod(y, 2)) == 1) magenta else black;
        }
    }

    const _errorCheckerboardImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try _errorCheckerboardImage.uploadDataToImage(device, vma.handle, &pixels);

    var sampl: vk.c.VkSamplerCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.c.VK_FILTER_NEAREST,
        .minFilter = vk.c.VK_FILTER_NEAREST,
    };

    var _defaultSamplerLinear: vk.c.VkSampler = undefined;
    var _defaultSamplerNearest: vk.c.VkSampler = undefined;
    _ = vk.c.vkCreateSampler(device.handle, &sampl, null, &_defaultSamplerNearest);
    sampl.magFilter = vk.c.VK_FILTER_LINEAR;
    sampl.minFilter = vk.c.VK_FILTER_LINEAR;
    _ = vk.c.vkCreateSampler(device.handle, &sampl, null, &_defaultSamplerLinear);

    // //TODO: GET RID OF
    var compute_descriptor_config: vk.descriptor.Layout.Config = .{};
    compute_descriptor_config.addBinding(0, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    const compute_descriptor_layout: vk.descriptor.Layout = try .init(device, &compute_descriptor_config, vk.c.VK_SHADER_STAGE_COMPUTE_BIT);

    var graphics_descriptor_config: vk.descriptor.Layout.Config = .{};
    graphics_descriptor_config.addBinding(0, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    const graphics_descriptor_layout: vk.descriptor.Layout = try .init(device, &graphics_descriptor_config, vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT);

    var descriptor_gpu_scene_data_config: vk.descriptor.Layout.Config = .{};
    descriptor_gpu_scene_data_config.addBinding(0, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
    const descriptor_gpu_scene_data: vk.descriptor.Layout = try .init(
        device,
        &descriptor_gpu_scene_data_config,
        vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
    );

    var _singleImageDescriptorLayout_config: vk.descriptor.Layout.Config = .{};
    _singleImageDescriptorLayout_config.addBinding(0, vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
    const _singleImageDescriptorLayout: vk.descriptor.Layout = try .init(
        device,
        &_singleImageDescriptorLayout_config,
        vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
    );

    const shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient.comp.spv");
    const gradient_color: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient_color.comp.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, shader, null);
    defer vk.c.vkDestroyShaderModule(device.handle, gradient_color, null);

    var pipelines: [16]vk.Pipeline = undefined;
    var config_comp1: vk.Pipeline.Compute.Config = .{
        .descriptor_set_layouts = &.{compute_descriptor_layout.handle},
        .shader = .{
            .module = shader,
        },
    };
    pipelines[0] = try .initCompute(device, &config_comp1);
    pipelines[0].compute.data.data1 = .{ 1, 0, 0, 1 };
    pipelines[0].compute.data.data2 = .{ 0, 0, 1, 1 };

    var config_comp2: vk.Pipeline.Compute.Config = .{
        .descriptor_set_layouts = &.{compute_descriptor_layout.handle},
        .shader = .{
            .module = gradient_color,
        },
    };
    pipelines[1] = try .initCompute(device, &config_comp2);
    pipelines[1].compute.data.data2 = .{ 0.1, 0.2, 0.4, 0.97 };

    const frag: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle.frag.spv");
    const vert: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle.vert.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, vert, null);
    defer vk.c.vkDestroyShaderModule(device.handle, frag, null);

    var state: []const vk.c.VkDynamicState = &.{ vk.c.VK_DYNAMIC_STATE_VIEWPORT, vk.c.VK_DYNAMIC_STATE_SCISSOR };
    var config_graphics: vk.Pipeline.Graphics.Config = .{
        .vertex_shaders = .{
            .module = vert,
        },
        .fragment_shaders = .{
            .module = frag,
        },
        .descriptor_set_layouts = &.{graphics_descriptor_layout.handle},
        .push_constants = &.{},
    };
    config_graphics.viewport_state.scissorCount = 1;
    config_graphics.viewport_state.viewportCount = 1;
    config_graphics.dynamic_state.dynamicStateCount = 2;
    config_graphics.dynamic_state.pDynamicStates = &state[0];
    config_graphics.render_info.colorAttachmentCount = 1;
    config_graphics.render_info.pColorAttachmentFormats = &draw_image.format;
    config_graphics.render_info.depthAttachmentFormat = depth_image.format;
    config_graphics.enableDepthTesting(vk.c.VK_TRUE, vk.c.VK_COMPARE_OP_GREATER_OR_EQUAL);
    pipelines[2] = try .initGraphics(device, &config_graphics);

    const frag_shader_triangle: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/tex_image.frag.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, frag_shader_triangle, null);

    const vert_shader_triangle: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle_mesh.vert.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, vert_shader_triangle, null);

    var config_mesh: vk.Pipeline.Graphics.Config = .{
        .fragment_shaders = .{
            .module = frag_shader_triangle,
        },
        .vertex_shaders = .{
            .module = vert_shader_triangle,
        },
        .descriptor_set_layouts = &.{_singleImageDescriptorLayout.handle},
        .push_constants = &.{.{
            .offset = 0,
            .size = @sizeOf(vk.Mesh.GPUDrawPushConstants),
            .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
        }},
    };
    pipelines[3] = try .initGraphics(device, &config_mesh);

    // const mesh_vert: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/colored_triangle_mesh.vert.spv");
    // defer vk.c.vkDestroyShaderModule(device.handle, mesh_vert, null);
    // var config_mesh: vk.Pipeline.Graphics.Config = .{
    //     .fragment_shaders = .{
    //         .module = frag,
    //     },
    //     .vertex_shaders = .{
    //         .module = mesh_vert,
    //     },
    //     .descriptor_set_layouts = &.{graphics_descriptor._drawImageDescriptorLayou},
    //     .push_constants = &.{.{
    //         .offset = 0,
    //         .size = @sizeOf(vk.Mesh.GPUDrawPushConstants),
    //         .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
    //     }},
    // };
    // config_mesh.viewport_state.scissorCount = 1;
    // config_mesh.viewport_state.viewportCount = 1;
    // config_mesh.dynamic_state.dynamicStateCount = 2;
    // config_mesh.dynamic_state.pDynamicStates = &state[0];
    // config_mesh.render_info.colorAttachmentCount = 1;
    // config_mesh.render_info.pColorAttachmentFormats = &draw_image.format;
    // config_mesh.render_info.depthAttachmentFormat = depth_image.format;
    // config_mesh.rasterization_state.cullMode = vk.c.VK_CULL_MODE_NONE;
    // config_mesh.enableDepthTesting(vk.c.VK_TRUE, vk.c.VK_COMPARE_OP_GREATER_OR_EQUAL);
    // // config_mesh.setBlendingDestinationColorBlendFactor(vk.c.VK_BLEND_FACTOR_ONE);
    // pipelines[3] = try .initGraphics(device, &config_mesh);

    // std.debug.print("Address {*}\n", .{instance.handle});

    return .{
        .allocator = allocator,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .pipelines = pipelines,
        .current_pipeline = 0,
        .max_pipelines = 4,
        .vma = vma,
        .draw_image = draw_image,
        .depth_image = depth_image,
        ._gpuSceneDataDescriptorLayout = descriptor_gpu_scene_data,
        ._singleImageDescriptorLayout = _singleImageDescriptorLayout,
        .compute_descriptor_layout = compute_descriptor_layout,
        .graphics_descriptor_layout = graphics_descriptor_layout,
        .scene_data = std.mem.zeroes(GPUSceneData),
        ._whiteImage = _whiteImage,
        ._blackImage = _blackImage,
        ._greyImage = _greyImage,
        ._errorCheckerboardImage = _errorCheckerboardImage,
        ._defaultSamplerLinear = _defaultSamplerLinear,
        ._defaultSamplerNearest = _defaultSamplerNearest,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.handle);
    self.swapchain.deinit(self.device);

    self.descriptor.deinit(self.device);
    self.descriptor_graphics.deinit(self.device);
    for (0..self.max_pipelines) |i|
        self.pipelines[i].deinit(self.device);
    self.draw_image.deinit(self.vma, self.device);
    self.depth_image.deinit(self.vma, self.device);
    self._blackImage.deinit(self.vma, self.device);
    self._greyImage.deinit(self.vma, self.device);
    self._errorCheckerboardImage.deinit(self.vma, self.device);
    self._whiteImage.deinit(self.vma, self.device);

    self.the_mesh.deinit(self.vma.handle);
    for (self.meshes.items) |mesh| {
        mesh.deinit(self.vma.handle);
    }
    self.meshes.deinit(allocator);

    self.vma.deinit();

    self.device.deinit();
    self.surface.deinit(self.instance);
    self.debug_messenger.deinit(self.instance);
    self.instance.deinit();
}

pub fn reCreateSwapchain(self: *@This(), width: usize, height: usize) !void {
    try self.swapchain.recreate(
        self.physical_device,
        self.device,
        self.surface,
        @intCast(width),
        @intCast(height),
    );
    const scale: f32 = 1;
    const scaled_height: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.image_extent.height))) * scale;
    const scaled_width: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.image_extent.width))) * scale;
    self.draw_image.image_extent.height = @intFromFloat(scaled_height);
    self.draw_image.image_extent.width = @intFromFloat(scaled_width);
}

pub fn draw(self: *@This(), time: f32) !void {
    var image_index: u32 = undefined;
    const current_frame = self.swapchain.frames[self.swapchain.current_frame_inflight % self.swapchain.frames.len];
    try vk.check(vk.c.vkWaitForFences(self.device.handle, 1, &current_frame.render_fence, 1, 1000000000));
    try vk.check(vk.c.vkResetFences(self.device.handle, 1, &current_frame.render_fence));
    const aquire_result = vk.c.vkAcquireNextImageKHR(
        self.device.handle,
        self.swapchain.swapchain,
        1000000000,
        current_frame.swapchain_semaphore,
        null,
        &image_index,
    );
    if (aquire_result == vk.c.VK_ERROR_OUT_OF_DATE_KHR) {
        self.resize_request = true;
        return;
    }
    current_frame.descriptor.clearPools(self.allocator, self.device);

    const cmd_buffer = current_frame.command_buffer;
    try vk.check(vk.c.vkResetCommandBuffer(cmd_buffer, 0));
    var cmd_begin_info: vk.c.VkCommandBufferBeginInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = vk.c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try vk.check(vk.c.vkBeginCommandBuffer(cmd_buffer, &cmd_begin_info));

    var draw_image_barrier: vk.Barrier = .init(cmd_buffer, self.draw_image.image, vk.c.VK_IMAGE_ASPECT_COLOR_BIT);
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

    draw_image_barrier.transition(
        vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        vk.c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    );
    var depth_image_barrier: vk.Barrier = .init(cmd_buffer, self.depth_image.image, vk.c.VK_IMAGE_ASPECT_DEPTH_BIT);
    depth_image_barrier.transition(
        vk.c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | vk.c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        vk.c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk.c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    );
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
        .clearValue = .{
            .color = .{
                .float32 = .{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
    };
    var depth_attachment: vk.c.VkRenderingAttachmentInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.image_view,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = vk.c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .depthStencil = .{
                .depth = 0,
            },
        },
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
        .pDepthAttachment = &depth_attachment,
        .pStencilAttachment = null,
    };

    vk.c.vkCmdBeginRendering(cmd_buffer, &renderInfo);

    vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[2].get().handle);

    const gpuSceneDataBuffer: vk.Buffer = .init(self.vma, @sizeOf(GPUSceneData), vk.v.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.VMA_MEMORY_USAGE_CPU_TO_GPU);
    defer gpuSceneDataBuffer.deinit(self.vma);

    //TODO: try removing the vma get info
    self.vma.copyToAllocation(GPUSceneData, self.scene_data, gpuSceneDataBuffer.vma_allocation, gpuSceneDataBuffer.info);

    const globalDescriptor: vk.c.VkDescriptorSet = current_frame.descriptor.allocate(self.allocator, self.device, self._gpuSceneDataDescriptorLayout, null);

    {
        const writer: vk.descriptor.Writer = .{};
        writer.appendBuffer(0, gpuSceneDataBuffer.buffer, @sizeOf(GPUSceneData), 0, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        writer.updateSet(self.device, globalDescriptor);
    }

    //TODO: ADD WRITER
    // var writer: vk.DescriptorAllocatorGrowable.Writer = .{};
    // writer.Image(
    //     self.allocator,
    //     0,
    //     self.draw_image.image_view,
    //     vk.c.VK_NULL_HANDLE,
    //     vk.c.VK_IMAGE_LAYOUT_GENERAL,
    //     vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
    // );
    // writer.updateSet(self.device, )

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

    const image_set: vk.c.VkDescriptorSet = current_frame.descriptor.allocate(self.allocator, self.device, self._singleImageDescriptorLayout, null);
    {
        const writer: vk.DescriptorAllocatorGrowable.Writer = .{};
        writer.appendImage(0, self._errorCheckerboardImage.image_view, self._defaultSamplerNearest, vk.c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL, vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
        writer.updateSet(self.device, image_set);
    }
    vk.c.vkCmdBindDescriptorSets(
        cmd_buffer,
        .vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        self.pipelines[3].get().handle,
        0,
        1,
        &image_set,
        0,
        null,
    );

    //projection matrix + view + model
    const view: nz.Mat4x4(f32) = .translate(.{ 0, 0, -5 });
    var projection: nz.Mat4x4(f32) = .perspective(
        70,
        @floatFromInt(self.draw_image.image_extent.width / self.draw_image.image_extent.height),
        10000,
        0.1,
    );
    projection.d[5] *= -1;

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

    var swapchain_image_barrier: vk.Barrier = .init(cmd_buffer, self.swapchain.vk_images[image_index], vk.c.VK_IMAGE_ASPECT_COLOR_BIT);
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

    const present_result = vk.c.vkQueuePresentKHR(self.device.graphics_queue, &present_info);
    if (present_result == vk.c.VK_ERROR_OUT_OF_DATE_KHR) {
        self.resize_request = true;
    }

    self.swapchain.current_frame_inflight += 1;
}

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
        std.log.err("Failed to parse OBJ file: {s}, error code: {d}", .{ path, result });
        return error.ObjParsed;
    }

    var vertices_list: std.ArrayList(vk.Mesh.Vertex) = .empty;
    var indecies_list: std.ArrayList(u32) = .empty;
    defer vertices_list.deinit(allocator);
    defer indecies_list.deinit(allocator);

    var face_offset: usize = 0;
    var face_idx: usize = 0;
    while (face_idx < @as(usize, @intCast(attribs.num_faces))) : (face_idx += 1) {
        const face_vertex_count: i32 = attribs.face_num_verts[face_idx];
        if (face_vertex_count == 3) {
            var i: usize = 0;
            while (i < 3) : (i += 1) {
                const index = attribs.faces[face_offset + i];

                const pos_x = attribs.vertices[@as(usize, @intCast(3 * index.v_idx))];
                const pos_y = attribs.vertices[@as(usize, @intCast(3 * index.v_idx + 1))];
                const pos_z = attribs.vertices[@as(usize, @intCast(3 * index.v_idx + 2))];

                const vertex: vk.Mesh.Vertex = .{
                    .position = .{ pos_x, pos_y, pos_z, 1.0 },
                };

                try vertices_list.append(allocator, vertex);
                try indecies_list.append(allocator, @intCast(indecies_list.items.len));
            }
            face_offset += @as(usize, @intCast(face_vertex_count));
        }
    }

    if (vertices_list.items.len > 0 and indecies_list.items.len > 0) {
        std.debug.print("\nADDED MESH {s}\n\n", .{path});

        try self.meshes.append(allocator, try .init(
            self.device,
            self.vma.handle,
            indecies_list.items,
            vertices_list.items,
        ));
    } else {
        std.debug.print("\nNo valid mesh data found in {s}\n\n", .{path});
    }

    // Free tiny_obj_loader memory
    tiny_obj.tinyobj_attrib_free(&attribs);
    tiny_obj.tinyobj_shapes_free(shapes, num_shapes);
    tiny_obj.tinyobj_materials_free(materials, num_materials);
}
