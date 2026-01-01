const std = @import("std");
const nz = @import("numz");
pub const vk = @import("vulkan/vulkan.zig");
const Obj = @import("asset/Obj.zig");
const tiny_obj = @import("tiny_obj_loader");
pub const c = @import("c.zig");
pub const Camera = @import("Camera.zig");

//TODO: FIX temporarly SOLUTION, (build.zig)?
comptime {
    _ = c;
}

//TODO: Find out where this should be?
const RenderObject = struct {
    mesh: vk.Mesh,
    transform: nz.Mat4x4(f32),
    material: vk.Material.Instance,
};

//TODO: WILL REMOVE (but exist temporarly for the learnding):
defaultData: vk.Material.Instance,
metalRoughMaterial: vk.Material.GltfMetallicRoughness,
materialBuffer: vk.Buffer,
materialResources: vk.Material.GltfMetallicRoughness.Resources,
pipelines: [16]vk.Pipeline,
max_pipelines: usize = 0,
current_pipeline: usize = 0,
meshes: std.ArrayList(vk.Mesh) = .empty,
graphics_descriptor_layout: vk.descriptor.Layout,
_singleImageDescriptorLayout: vk.descriptor.Layout,
_gpuSceneDataDescriptorLayout: vk.descriptor.Layout,
_drawImageDescitporLayour: vk.descriptor.Layout,
globalDescriptorAllocator: vk.descriptor.Growable,
_drawImageDescriptor: vk.c.VkDescriptorSet,
scene_data: vk.GPUSceneData,
_whiteImage: vk.Image,
_blackImage: vk.Image,
_greyImage: vk.Image,
_errorCheckerboardImage: vk.Image,
_defaultSamplerLinear: vk.c.VkSampler,
_defaultSamplerNearest: vk.c.VkSampler,
mainDrawContext: vk.Node.DrawContext = undefined,
loaded_nodes: [16]vk.Node = undefined,
node_count: usize = 0,
camera: Camera = .{ .position = .{ 0, 0, 5 } },

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

pub const Config = struct {
    instance: struct {
        extensions: ?[]const [*:0]const u8 = null,
        layers: ?[]const [*:0]const u8 = null,
        debug_config: vk.DebugMessenger.Config = .{},
    } = .{},

    device: struct {
        extensions: ?[]const [*:0]const u8 = null,
    } = .{},

    surface: struct {
        data: ?*anyopaque = null,
        init: ?*const fn (vk.Instance, *anyopaque) anyerror!*anyopaque = null,
    } = .{},

    swapchain: struct {
        width: u32 = 0,
        heigth: u32 = 0,
    },
};

pub fn init(allocator: std.mem.Allocator, config: Config) !@This() {
    const instance: vk.Instance = try .init(config.instance.extensions, config.instance.layers);
    const debug_messenger: vk.DebugMessenger = try .init(instance, config.instance.debug_config);
    const surface: vk.Surface = if (config.surface.init != null and config.surface.data != null) .{ .handle = @ptrCast(try config.surface.init.?(instance, config.surface.data.?)) } else try vk.Surface.init(instance);
    const physical_device: vk.PhysicalDevice = try .find(instance, surface);
    const device: vk.Device = try .init(physical_device, config.device.extensions);
    const vma: vk.Vma = try .init(instance, physical_device, device);
    const swapchain: vk.Swapchain = try .init(allocator, vma, physical_device, device, surface, config.swapchain.width, config.swapchain.heigth);

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
    var white: u32 = nz.color.Rgba(u8).white.toU32();
    const _whiteImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );

    try _whiteImage.uploadDataToImage(device, vma.handle, &white);

    var grey: u32 = nz.color.Rgba(u8).grey.toU32();
    const _greyImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try _greyImage.uploadDataToImage(device, vma.handle, &grey);

    var black: u32 = nz.color.Rgba(u8).black.toU32();
    const _blackImage: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try _blackImage.uploadDataToImage(device, vma.handle, &black);

    //checkerboard image
    const magenta: u32 = nz.color.Rgba(u8).new(255, 0, 255, 255).toU32();
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
        .{ .width = 16, .height = 16, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
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

    var sizes = [_]vk.descriptor.Growable.PoolSizeRatio{
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .ratio = 2 },
    };

    var globalDescriptorAllocator: vk.descriptor.Growable = try .init(allocator, device, 10, &sizes);

    const _drawImageDescriptorLayoutlayout: vk.descriptor.Layout = try .init(
        device,
        &[_]vk.c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                .stageFlags = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
            },
        },
    );
    const _drawImageDescriptor = try globalDescriptorAllocator.allocate(device, _drawImageDescriptorLayoutlayout.handle, null);

    var imgInfo: vk.c.VkDescriptorImageInfo = .{
        .imageView = draw_image.image_view,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_GENERAL,
    };

    const drawImageWrite: vk.c.VkWriteDescriptorSet = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = _drawImageDescriptor,
        .descriptorCount = 1,
        .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &imgInfo,
    };
    vk.c.vkUpdateDescriptorSets(device.handle, 1, &drawImageWrite, 0, null);

    const graphics_descriptor_layout: vk.descriptor.Layout = try .init(
        device,
        &[_]vk.c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        },
    );

    const descriptor_gpu_scene_data: vk.descriptor.Layout = try .init(
        device,
        &[_]vk.c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT | vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        },
    );

    const _singleImageDescriptorLayout: vk.descriptor.Layout = try .init(
        device,
        &[_]vk.c.VkDescriptorSetLayoutBinding{
            .{
                .binding = 0,
                .descriptorCount = 1,
                .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                .stageFlags = vk.c.VK_SHADER_STAGE_FRAGMENT_BIT,
            },
        },
    );

    const shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient.comp.spv");
    const gradient_color: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/gradient_color.comp.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, shader, null);
    defer vk.c.vkDestroyShaderModule(device.handle, gradient_color, null);

    var pipelines: [16]vk.Pipeline = undefined;
    var config_comp1: vk.Pipeline.Compute.Config = .{
        .descriptor_set_layouts = &.{_drawImageDescriptorLayoutlayout.handle},
        .shader = .{
            .module = shader,
        },
    };

    pipelines[0] = try .initCompute(device, &config_comp1);
    pipelines[0].compute.data.data1 = .{ 1, 0, 0, 1 };
    pipelines[0].compute.data.data2 = .{ 0, 0, 1, 1 };

    var config_comp2: vk.Pipeline.Compute.Config = .{
        .descriptor_set_layouts = &.{_drawImageDescriptorLayoutlayout.handle},
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
    config_mesh.viewport_state.scissorCount = 1;
    config_mesh.viewport_state.viewportCount = 1;
    config_mesh.dynamic_state.dynamicStateCount = 2;
    config_mesh.dynamic_state.pDynamicStates = &[_]c_uint{
        vk.c.VK_DYNAMIC_STATE_VIEWPORT,
        vk.c.VK_DYNAMIC_STATE_SCISSOR,
    };
    config_mesh.enableDepthTesting(vk.c.VK_TRUE, vk.c.VK_COMPARE_OP_GREATER_OR_EQUAL);
    config_mesh.render_info.depthAttachmentFormat = depth_image.format;
    pipelines[3] = try .initGraphics(device, &config_mesh);

    var metalRoughMaterial: vk.Material.GltfMetallicRoughness = try .initBuildPipelines(device, descriptor_gpu_scene_data, draw_image, depth_image);
    var materialBuffer = try vk.Buffer.init(vma.handle, @sizeOf(vk.Material.GltfMetallicRoughness.Constants), vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);

    // Initialize the uniform data with proper values BEFORE copying
    const sceneUniformData: vk.Material.GltfMetallicRoughness.Constants = .{
        .color_factores = .{ 1, 1, 1, 1 },
        .metal_rough_factors = .{ 1, 0.5, 0, 0 },
        .extra = std.mem.zeroes([14]nz.Vec4(f32)),
    };

    // Copy the initialized data to GPU memory
    vma.copyToAllocation(
        vk.Material.GltfMetallicRoughness.Constants,
        sceneUniformData,
        materialBuffer.vma_allocation,
        &materialBuffer.info,
    );

    const materialResources: vk.Material.GltfMetallicRoughness.Resources = .{
        .color_image = _whiteImage,
        .color_sampler = _defaultSamplerLinear,
        .metal_rough_image = _whiteImage,
        .metal_rough_sampler = _defaultSamplerLinear,
        .data_buffer = materialBuffer.buffer,
        .data_buffer_offset = 0, // This is already aligned since it's the start of thconstuffer
    };

    const defaultData = try metalRoughMaterial.writeMaterial(
        device,
        vk.Material.Pass.main_color,
        materialResources,
        &globalDescriptorAllocator,
    );

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
        .graphics_descriptor_layout = graphics_descriptor_layout,
        ._drawImageDescitporLayour = _drawImageDescriptorLayoutlayout,
        .scene_data = std.mem.zeroes(vk.GPUSceneData),
        ._whiteImage = _whiteImage,
        ._blackImage = _blackImage,
        ._greyImage = _greyImage,
        ._errorCheckerboardImage = _errorCheckerboardImage,
        ._defaultSamplerLinear = _defaultSamplerLinear,
        ._defaultSamplerNearest = _defaultSamplerNearest,
        .globalDescriptorAllocator = globalDescriptorAllocator,
        ._drawImageDescriptor = _drawImageDescriptor,
        .metalRoughMaterial = metalRoughMaterial,
        .materialBuffer = materialBuffer,
        .materialResources = materialResources,
        .defaultData = defaultData,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.handle);
    std.debug.print("NOW FREEING\n", .{});
    std.log.debug("", .{});
    self.swapchain.deinit(self.vma, self.device);

    for (0..self.max_pipelines) |i|
        self.pipelines[i].deinit(self.device);
    self.draw_image.deinit(self.vma, self.device);
    self.depth_image.deinit(self.vma, self.device);
    self._blackImage.deinit(self.vma, self.device);
    self._greyImage.deinit(self.vma, self.device);
    self._whiteImage.deinit(self.vma, self.device);
    self._errorCheckerboardImage.deinit(self.vma, self.device);

    vk.c.vkDestroySampler(self.device.handle, self._defaultSamplerLinear, null);
    vk.c.vkDestroySampler(self.device.handle, self._defaultSamplerNearest, null);
    self._gpuSceneDataDescriptorLayout.deinit(self.device);
    self.graphics_descriptor_layout.deinit(self.device);
    self._singleImageDescriptorLayout.deinit(self.device);
    self._drawImageDescitporLayour.deinit(self.device);
    self.metalRoughMaterial.deinit(self.device);
    self.materialBuffer.deinit(self.vma.handle);

    self.globalDescriptorAllocator.deinit(self.device);

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

    const scaled_height: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.image_extent.height)));
    const scaled_width: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.image_extent.width)));
    self.draw_image.image_extent.height = @intFromFloat(scaled_height);
    self.draw_image.image_extent.width = @intFromFloat(scaled_width);
}

pub fn draw(self: *@This(), time: f32) !void {
    var image_index: u32 = undefined;
    var current_frame = &self.swapchain.frames[self.swapchain.current_frame_inflight % self.swapchain.frames.len];
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
    if (aquire_result == vk.c.VK_ERROR_OUT_OF_DATE_KHR or aquire_result == vk.c.VK_SUBOPTIMAL_KHR) {
        self.resize_request = true;
        return;
    }
    const render_semaphore: vk.c.VkSemaphore = self.swapchain.render_semaphores[image_index];
    try current_frame.descriptor.clearPools(self.device);
    current_frame.gpu_scene.deinit(self.vma.handle);

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
    // std.debug.print("time converted {d} time {d}\r", .{ self.current_pipeline, time });

    const pipeline: vk.Pipeline = self.pipelines[self.current_pipeline];

    vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_COMPUTE, pipeline.get().handle);

    vk.c.vkCmdBindDescriptorSets(
        cmd_buffer,
        vk.c.VK_PIPELINE_BIND_POINT_COMPUTE,
        pipeline.get().layout,
        0,
        1,
        &self._drawImageDescriptor,
        0,
        null,
    );

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

    current_frame.gpu_scene = try .init(self.vma.handle, @sizeOf(vk.GPUSceneData), vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);

    //TODO: try removing the vma get info
    self.vma.copyToAllocation(vk.GPUSceneData, self.scene_data, current_frame.gpu_scene.vma_allocation, &current_frame.gpu_scene.info);
    const globalDescriptor: vk.c.VkDescriptorSet = try current_frame.descriptor.allocate(self.device, self._gpuSceneDataDescriptorLayout.handle, null);
    {
        var writer: vk.descriptor.Writer = .{};
        writer.appendBuffer(0, current_frame.gpu_scene.buffer, @sizeOf(vk.GPUSceneData), 0, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        writer.updateSet(self.device, globalDescriptor);
    }

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

    // //Triangle
    vk.c.vkCmdDraw(cmd_buffer, 3, 1, 0, 0);

    //The mesh
    //TODO: ====================================
    //TODO: ====================================
    //TODO: ====================================
    self.mainDrawContext.clear();
    const top_matrix: nz.Transform3D(f32) = .{
        .position = .{ 0, 0, -2 },
        .rotation = .{ 0, 0, 0 },
    };
    self.loaded_nodes[0].draw(top_matrix, &self.mainDrawContext);
    const view = self.camera.getViewMatrix();
    // const view = nz.Mat4x4(f32).identity;
    var projection = nz.Mat4x4(f32).perspective(
        1.5,
        (@as(f32, @floatFromInt(self.draw_image.image_extent.width)) / @as(f32, @floatFromInt(self.draw_image.image_extent.height))),
        0.1,
        10000,
    );
    projection.d[5] *= -1;
    self.scene_data.proj = projection.d;
    self.scene_data.view = view.d;
    self.scene_data.viewproj = projection.mul(view).d;
    self.scene_data.ambient_color = @splat(1);
    self.scene_data.sunlight_color = @splat(1);
    self.scene_data.sunlight_direction = .{ 0, 1, 0.5, 1 };

    // std.debug.print("\nsceneDATA {any}\n", .{self.scene_data});
    for (0..self.mainDrawContext.count) |i| {
        // std.debug.print("\nRENDER NODE\n", .{});
        const opaque_draw = &self.mainDrawContext.opaque_surfaces[i];

        vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, opaque_draw.material_instance.pipeline.get().handle);

        //TODO:CONTINUE from here.
        vk.c.vkCmdBindDescriptorSets(
            cmd_buffer,
            vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            opaque_draw.material_instance.pipeline.get().layout,
            0,
            1,
            &globalDescriptor,
            0,
            null,
        );
        vk.c.vkCmdBindDescriptorSets(
            cmd_buffer,
            vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            opaque_draw.material_instance.pipeline.get().layout,
            1,
            1,
            &opaque_draw.material_instance.descriptor_set,
            0,
            null,
        );

        vk.c.vkCmdBindIndexBuffer(cmd_buffer, opaque_draw.index_buffer, 0, vk.c.VK_INDEX_TYPE_UINT32);

        // std.debug.print("world_matrix: {any}\n", .{opaque_draw.transform.toMat4x4().d});

        var push_constant: vk.Mesh.GPUDrawPushConstants = .{
            .world_matrix = opaque_draw.transform.toMat4x4().d,
            .vertex_buffer = opaque_draw.vertex_buffer_address,
        };
        vk.c.vkCmdPushConstants(cmd_buffer, opaque_draw.material_instance.pipeline.get().layout, vk.c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(vk.Mesh.GPUDrawPushConstants), &push_constant);

        vk.c.vkCmdDrawIndexed(cmd_buffer, opaque_draw.index_count, 1, opaque_draw.first_index, 0, 0);
    }

    //
    //
    // vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, self.pipelines[3].get().handle);
    //
    // const image_set: vk.c.VkDescriptorSet = try current_frame.descriptor.allocate(self.device, self._singleImageDescriptorLayout.handle, null);
    // {
    //     var writer: vk.descriptor.Writer = .{};
    //     writer.appendImage(0, self._errorCheckerboardImage.image_view, self._defaultSamplerNearest, vk.c.VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL, vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER);
    //     writer.updateSet(self.device, image_set);
    // }
    //
    // vk.c.vkCmdBindDescriptorSets(
    //     cmd_buffer,
    //     vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS,
    //     self.pipelines[3].get().layout,
    //     0,
    //     1,
    //     &image_set,
    //     0,
    //     null,
    // );
    //
    // var push: vk.Mesh.GPUDrawPushConstants = .{
    //     .vertex_buffer = self.meshes.items[0].vertex_buffer_address,
    //     .world_matrix = projection.mul(self.scene_data.view).d,
    // };
    //
    // vk.c.vkCmdPushConstants(
    //     cmd_buffer,
    //     self.pipelines[3].get().layout,
    //     vk.c.VK_SHADER_STAGE_VERTEX_BIT,
    //     0,
    //     @sizeOf(vk.Mesh.GPUDrawPushConstants),
    //     &push,
    // );
    // vk.c.vkCmdBindIndexBuffer(cmd_buffer, self.meshes.items[0].index_buffeconstuffer, 0, vk.c.VK_INDEX_TYPE_UINT32);
    // vk.c.vkCmdDrawIndexed(cmd_buffer, self.meshes.items[0].indecies_count, 1, 0, 0, 0);
    //TODO:===============================
    //TODO: ====================================
    //TODO: ====================================

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
            .value = 0,
        },
        .signalSemaphoreInfoCount = 1,
        .pSignalSemaphoreInfos = &.{
            .sType = vk.c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = render_semaphore,
            .stageMask = vk.c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .value = 0,
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
        .pWaitSemaphores = &render_semaphore,
        .waitSemaphoreCount = 1,
        .pImageIndices = &image_index,
    };

    const present_result = vk.c.vkQueuePresentKHR(self.device.graphics_queue, &present_info);
    if (present_result == vk.c.VK_ERROR_OUT_OF_DATE_KHR or present_result == vk.c.VK_SUBOPTIMAL_KHR) {
        self.resize_request = true;
        return;
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

                var uv_x: f32 = 0;
                var uv_y: f32 = 0;

                if (index.vt_idx >= 0) {
                    uv_x = attribs.texcoords[@intCast(2 * index.vt_idx)];
                    uv_y = attribs.texcoords[@intCast(2 * index.vt_idx + 1)];
                }

                const vertex: vk.Mesh.Vertex = .{
                    .position = .{ pos_x, pos_y, pos_z },
                    .uv_x = uv_x,
                    .uv_y = uv_y,
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
            allocator,
            self.vma.handle,
            indecies_list.items,
            vertices_list.items,
        ));
        //TODO: add sufaces?
        self.loaded_nodes[self.node_count] = .{
            .material = &self.defaultData,
            .mesh = self.meshes.getLast(),
            .world_transform = .{},
            .local_transform = .{},
        };
        std.debug.print("MATRIX on init: {any}\n", .{self.loaded_nodes[self.node_count].world_transform.toMat4x4()});
        self.node_count += 1;
    } else {
        std.debug.print("\nNo valid mesh data found in {s}\n\n", .{path});
    }

    // Free tiny_obj_loader memory
    tiny_obj.tinyobj_attrib_free(&attribs);
    tiny_obj.tinyobj_shapes_free(shapes, num_shapes);
    tiny_obj.tinyobj_materials_free(materials, num_materials);
}
