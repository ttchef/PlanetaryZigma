const std = @import("std");
const nz = @import("numz");
const WorldModule = @import("World");
const LoadedGltf = @import("asset/LoadedGltf.zig");
pub const vk = @import("vulkan/vulkan.zig");
pub const Camera = @import("World").Camera;
pub const c = @import("c.zig");

//TODO: FIX temporarly SOLUTION, (build.zig)?
comptime {
    _ = c;
}

//models
loaded_scenes: std.ArrayList(LoadedGltf) = .empty,
meshes: std.ArrayList(vk.Mesh) = .empty,

//Default values
white_image: vk.Image,
black_image: vk.Image,
error_checkerboard_image: vk.Image,
default_sampler_linear: vk.c.VkSampler,
default_sampler_nearest: vk.c.VkSampler,
graphics_descriptor_layout: vk.descriptor.Layout,
gpu_scene_data_descriptor_layout: vk.descriptor.Layout,
global_descriptor_allocator: vk.descriptor.Growable,
draw_image_descriptor_layout: vk.descriptor.Layout,
draw_image_descriptor: vk.c.VkDescriptorSet,
scene_data: vk.GPUSceneData,

//GLTF
main_draw_context: vk.Node.DrawContext,
material_buffer: vk.Buffer,
metal_rough_material: vk.Material.GltfMetallicRoughness,
default_data: *const vk.Material.Instance,
material_resources: vk.Material.GltfMetallicRoughness.Resources,

//Debug
debug_pipeline: *vk.Pipeline,
debug_meshes: [3]vk.Mesh,

//Vulkan Render Specific
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

//NOTE: maybe not here?
last_pipeline: ?*const vk.Pipeline = null,
last_material: ?*const vk.Material.Instance = null,
last_index_buffer: vk.c.VkBuffer = null,

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
    const surface: vk.Surface = if (config.surface.init != null and config.surface.data != null) .{
        .handle = @ptrCast(try config.surface.init.?(instance, config.surface.data.?)),
    } else return error.configSurface;
    const physical_device: vk.PhysicalDevice = try .find(instance, surface);
    const device: vk.Device = try .init(physical_device, config.device.extensions);
    const vma: vk.Vma = try .init(instance, physical_device, device);
    const swapchain: vk.Swapchain = try .init(allocator, vma, physical_device, device, surface, config.swapchain.width, config.swapchain.heigth);

    var draw_image: vk.Image = try .init(
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
    var white: u32 = nz.color.Rgba(u8).white.toU32(.little);
    //new(255, 0, 255, 255).toU32();
    var white_image: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try white_image.uploadDataToImage(device, vma.handle, &white);

    var black: u32 = nz.color.Rgba(u8).black.toU32(.little);
    var black_image: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 1, .height = 1, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try black_image.uploadDataToImage(device, vma.handle, &black);

    //checkerboard image
    const magenta_color: u32 = nz.color.Rgba(u8).new(255, 0, 255, 255).toU32(.little);
    var pixels: [16 * 16]u32 = undefined;
    for (0..16) |x| {
        for (0..16) |y| {
            pixels[y * 16 + x] = if (std.math.pow(usize, @mod(x, 2), @mod(y, 2)) == 1) magenta_color else black;
        }
    }
    var error_checkerboard_image: vk.Image = try .init(
        vma.handle,
        device,
        vk.c.VK_FORMAT_R8G8B8A8_UNORM,
        .{ .width = 16, .height = 16, .depth = 1 },
        vk.c.VK_IMAGE_USAGE_SAMPLED_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        vk.c.VK_IMAGE_ASPECT_COLOR_BIT,
        false,
    );
    try error_checkerboard_image.uploadDataToImage(device, vma.handle, &pixels);

    var sampl: vk.c.VkSamplerCreateInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = vk.c.VK_FILTER_NEAREST,
        .minFilter = vk.c.VK_FILTER_NEAREST,
    };

    var default_sampler_linear: vk.c.VkSampler = undefined;
    var default_sampler_nearest: vk.c.VkSampler = undefined;
    _ = vk.c.vkCreateSampler(device.handle, &sampl, null, &default_sampler_nearest);
    sampl.magFilter = vk.c.VK_FILTER_LINEAR;
    sampl.minFilter = vk.c.VK_FILTER_LINEAR;
    _ = vk.c.vkCreateSampler(device.handle, &sampl, null, &default_sampler_linear);

    var sizes = [_]vk.descriptor.Growable.PoolSizeRatio{
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .ratio = 1 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .ratio = 1 },
        .{ .desciptor_type = vk.c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .ratio = 2 },
    };

    var global_descriptor_allocator: vk.descriptor.Growable = try .init(allocator, device, 10, &sizes);

    const draw_image_descriptor_layout: vk.descriptor.Layout = try .init(
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
    const draw_image_descriptor = try global_descriptor_allocator.allocate(device, draw_image_descriptor_layout.handle, null);

    var img_info: vk.c.VkDescriptorImageInfo = .{
        .imageView = draw_image.vk_imageview,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_GENERAL,
    };

    const draw_image_write: vk.c.VkWriteDescriptorSet = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstBinding = 0,
        .dstSet = draw_image_descriptor,
        .descriptorCount = 1,
        .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
        .pImageInfo = &img_info,
    };
    vk.c.vkUpdateDescriptorSets(device.handle, 1, &draw_image_write, 0, null);

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

    var metal_rough_material: vk.Material.GltfMetallicRoughness = try .initBuildPipelines(allocator, device, descriptor_gpu_scene_data, draw_image, depth_image);
    var material_buffer: vk.Buffer = try .init(vma.handle, @sizeOf(vk.Material.GltfMetallicRoughness.Constants), vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);

    // Initialize the uniform data with proper values BEFORE copying
    const scene_uniform_data: vk.Material.GltfMetallicRoughness.Constants = .{
        .color_factores = .{ 1, 1, 1, 1 },
        .metal_rough_factors = .{ 1, 0.5, 0, 0 },
        .extra = std.mem.zeroes([14]nz.Vec4(f32)),
    };

    // Copy the initialized data to GPU memory
    vma.copyToAllocation(
        vk.Material.GltfMetallicRoughness.Constants,
        scene_uniform_data,
        material_buffer.vma_allocation,
        &material_buffer.info,
    );

    const material_resources: vk.Material.GltfMetallicRoughness.Resources = .{
        .color_image = white_image,
        .color_sampler = default_sampler_linear,
        .metal_rough_image = white_image,
        .metal_rough_sampler = default_sampler_linear,
        .data_buffer = material_buffer.buffer,
        .data_buffer_offset = 0, // This is already aligned since it's the start of thconstuffer
    };

    const default_data = try allocator.create(vk.Material.Instance);
    default_data.* = try metal_rough_material.writeMaterial(
        device,
        vk.Material.Pass.main_color,
        material_resources,
        &global_descriptor_allocator,
    );

    //============
    //NOTE: DEBUG
    //============
    const mesh_frag_shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/debug.frag.spv");
    const mesh_vertex_shader: vk.c.VkShaderModule = try vk.LoadShader(device.handle, "zig-out/shaders/debug.vert.spv");
    defer vk.c.vkDestroyShaderModule(device.handle, mesh_frag_shader, null);
    defer vk.c.vkDestroyShaderModule(device.handle, mesh_vertex_shader, null);

    const matrix_range: vk.c.VkPushConstantRange = .{
        .offset = 0,
        .size = @sizeOf(vk.Mesh.GPUDrawPushConstants),
        .stageFlags = vk.c.VK_SHADER_STAGE_VERTEX_BIT,
    };

    var debug_pipeline_config: vk.Pipeline.Graphics.Config = .{
        .push_constants = &.{matrix_range},
        .descriptor_set_layouts = &.{
            descriptor_gpu_scene_data.handle,
        },
        .vertex_shaders = .{
            .module = mesh_vertex_shader,
        },
        .fragment_shaders = .{
            .module = mesh_frag_shader,
        },
    };
    debug_pipeline_config.viewport_state.scissorCount = 1;
    debug_pipeline_config.viewport_state.viewportCount = 1;
    debug_pipeline_config.dynamic_state.dynamicStateCount = 2;
    debug_pipeline_config.dynamic_state.pDynamicStates = &[_]c_uint{
        vk.c.VK_DYNAMIC_STATE_VIEWPORT,
        vk.c.VK_DYNAMIC_STATE_SCISSOR,
    };
    debug_pipeline_config.rasterization_state.polygonMode = vk.c.VK_POLYGON_MODE_LINE;

    const debug_pipeline = try allocator.create(vk.Pipeline);
    debug_pipeline.* = try .initGraphics(device, &debug_pipeline_config);
    var debug_material = try allocator.create(vk.Material.Instance);
    debug_material.pipeline = debug_pipeline;

    var debug_mehses: [3]vk.Mesh = undefined;
    // 8 corners of a cube
    const positions = [_][3]f32{
        .{ -0.5, -0.5, -0.5 }, // 0
        .{ 0.5, -0.5, -0.5 }, // 1
        .{ 0.5, 0.5, -0.5 }, // 2
        .{ -0.5, 0.5, -0.5 }, // 3
        .{ -0.5, -0.5, 0.5 }, // 4
        .{ 0.5, -0.5, 0.5 }, // 5
        .{ 0.5, 0.5, 0.5 }, // 6
        .{ -0.5, 0.5, 0.5 }, // 7
    };

    var vertices: [8]vk.Mesh.Vertex = undefined;
    for (positions, 0..) |pos, i| {
        vertices[i] = vk.Mesh.Vertex{
            .position = pos,
            .uv_x = 0,
            .uv_y = 0,
            .normal = .{ 0, 0, 0 },
            .color = .{ 1, 1, 1, 1 },
        };
    }

    // indices for triangles (two per face)

    var indices: [36]u32 = .{
        0, 1, 2, 2, 3, 0, // back
        4, 5, 6, 6, 7, 4, // front
        0, 4, 7, 7, 3, 0, // left
        1, 5, 6, 6, 2, 1, // right
        0, 1, 5, 5, 4, 0, // bottom
        3, 2, 6, 6, 7, 3, // top
    };

    debug_mehses[0] = try .init(
        allocator,
        vma.handle,
        "Box",
        device,
        &.{.{
            .index_start = 0,
            .index_count = @intCast(indices.len),
            .bounds = .{ .origin = @splat(0), .sphere_radius = 0, .extents = @splat(1) },
            .material = debug_material,
        }},
        indices[0..],
        vertices[0..],
    );

    return .{
        .allocator = allocator,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .swapchain = swapchain,
        .vma = vma,
        .draw_image = draw_image,
        .depth_image = depth_image,
        .debug_pipeline = debug_pipeline,
        .debug_meshes = debug_mehses,
        .gpu_scene_data_descriptor_layout = descriptor_gpu_scene_data,
        .graphics_descriptor_layout = graphics_descriptor_layout,
        .draw_image_descriptor_layout = draw_image_descriptor_layout,
        .scene_data = std.mem.zeroes(vk.GPUSceneData),
        .white_image = white_image,
        .black_image = black_image,
        .error_checkerboard_image = error_checkerboard_image,
        .default_sampler_linear = default_sampler_linear,
        .default_sampler_nearest = default_sampler_nearest,
        .global_descriptor_allocator = global_descriptor_allocator,
        .draw_image_descriptor = draw_image_descriptor,
        .material_buffer = material_buffer,
        .main_draw_context = .{},
        .metal_rough_material = metal_rough_material,
        .default_data = default_data,
        .material_resources = material_resources,
    };
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    _ = vk.c.vkDeviceWaitIdle(self.device.handle);
    std.debug.print("NOW FREEING\n", .{});
    std.log.debug("", .{});

    self.swapchain.deinit(self.vma, self.device);

    self.draw_image.deinit(self.vma, self.device);
    self.depth_image.deinit(self.vma, self.device);
    self.black_image.deinit(self.vma, self.device);
    self.white_image.deinit(self.vma, self.device);
    self.error_checkerboard_image.deinit(self.vma, self.device);

    vk.c.vkDestroySampler(self.device.handle, self.default_sampler_linear, null);
    vk.c.vkDestroySampler(self.device.handle, self.default_sampler_nearest, null);

    self.gpu_scene_data_descriptor_layout.deinit(self.device);
    self.graphics_descriptor_layout.deinit(self.device);
    self.draw_image_descriptor_layout.deinit(self.device);
    self.metal_rough_material.deinit(allocator, self.device);
    self.material_buffer.deinit(self.vma.handle);
    allocator.destroy(self.default_data);

    self.debug_pipeline.deinit(self.device);
    allocator.destroy(self.debug_pipeline);
    self.debug_meshes[0].deinit(self.allocator, self.vma.handle);

    for (self.loaded_scenes.items) |*scene| {
        scene.deinit(self.allocator, self.vma, self.device);
    }
    self.loaded_scenes.deinit(allocator);
    for (self.meshes.items) |*mesh| {
        mesh.deinit(allocator, self.vma.handle);
    }
    self.meshes.deinit(allocator);

    self.main_draw_context.deinit(allocator);
    self.global_descriptor_allocator.deinit(self.device);

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

    const scaled_height: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.height, self.draw_image.extent.height)));
    const scaled_width: f32 = @as(f32, @floatFromInt(@min(self.swapchain.extent.width, self.draw_image.extent.width)));
    self.draw_image.extent.height = @intFromFloat(scaled_height);
    self.draw_image.extent.width = @intFromFloat(scaled_width);
}

pub fn draw(self: *@This(), world: *WorldModule.World, time: f32) !void {
    var query = world.query(&.{ WorldModule.Player, WorldModule.Camera, nz.Transform3D(f32) });
    const entity = query.next().?;
    const camera = entity.getPtr(WorldModule.Camera, world).?;
    const camera_transform = entity.getPtr(nz.Transform3D(f32), world).?;

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

    var draw_image_barrier: vk.ImageBarrier = .init(cmd_buffer, self.draw_image.vk_image, vk.c.VK_IMAGE_ASPECT_COLOR_BIT);

    draw_image_barrier.transition(
        vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        vk.c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    );
    var depth_image_barrier: vk.ImageBarrier = .init(cmd_buffer, self.depth_image.vk_image, vk.c.VK_IMAGE_ASPECT_DEPTH_BIT);
    depth_image_barrier.transition(
        vk.c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        vk.c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | vk.c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        vk.c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk.c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
    );
    var color_attachment: vk.c.VkRenderingAttachmentInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .pNext = null,
        .imageView = self.draw_image.vk_imageview,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .resolveMode = vk.c.VK_RESOLVE_MODE_NONE,
        .resolveImageView = null,
        .resolveImageLayout = vk.c.VK_IMAGE_LAYOUT_UNDEFINED,
        .loadOp = vk.c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .color = .{
                .float32 = .{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
    };
    var depth_attachment: vk.c.VkRenderingAttachmentInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = self.depth_image.vk_imageview,
        .imageLayout = vk.c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
        .loadOp = vk.c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = vk.c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{
            .depthStencil = .{
                .depth = 1,
                .stencil = 0,
            },
        },
    };

    var render_info: vk.c.VkRenderingInfo = .{
        .sType = vk.c.VK_STRUCTURE_TYPE_RENDERING_INFO,
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

    vk.c.vkCmdBeginRendering(cmd_buffer, &render_info);

    current_frame.gpu_scene = try .init(self.vma.handle, @sizeOf(vk.GPUSceneData), vk.c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, vk.Vma.c.VMA_MEMORY_USAGE_CPU_TO_GPU);

    self.vma.copyToAllocation(vk.GPUSceneData, self.scene_data, current_frame.gpu_scene.vma_allocation, &current_frame.gpu_scene.info);
    const globalDescriptor: vk.c.VkDescriptorSet = try current_frame.descriptor.allocate(self.device, self.gpu_scene_data_descriptor_layout.handle, null);
    {
        var writer: vk.descriptor.Writer = .{};
        writer.appendBuffer(0, current_frame.gpu_scene.buffer, @sizeOf(vk.GPUSceneData), 0, vk.c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        writer.updateSet(self.device, globalDescriptor);
    }

    const view = getViewMatrix(camera_transform);
    // const view = nz.Mat4x4(f32).identity;
    // _ = camera_transform;
    var projection = perspective(
        camera.fov_rad,
        (@as(f32, @floatFromInt(self.draw_image.extent.width)) / @as(f32, @floatFromInt(self.draw_image.extent.height))),
        camera.near,
        camera.far,
    );
    // projection.d[5] *= -1;
    self.scene_data.proj = projection.d;
    self.scene_data.view = view.d;
    self.scene_data.viewproj = projection.mul(view).d;
    self.scene_data.ambient_color = @splat(1);
    self.scene_data.sunlight_color = .{ 0, 0, 0, 0 };
    self.scene_data.sunlight_direction = .{ @sin(time), 0, 0, 1 };

    // std.debug.print(
    //     \\sunlight_dir {any}
    //     \\time  {d}
    //     \\
    // , .{
    //     self.scene_data.sunlight_direction,
    //     time,
    // });
    //
    //

    // const top_matrix: nz.Transform3D(f32) = .{
    //     .position = .{ 0, 0, -2 },
    //     .rotation = @splat(0),
    //     .scale = @splat(-1),
    // };

    var draw_query = world.query(&.{ WorldModule.Model, nz.Transform3D(f32) });
    while (draw_query.next()) |entry| {
        self.main_draw_context.clear();
        const model = entry.get(WorldModule.Model, world).?;
        const transform = entry.get(nz.Transform3D(f32), world).?;
        self.last_index_buffer = null;
        self.last_material = null;
        self.last_pipeline = null;
        switch (model.model) {
            .mesh => |handle| {
                var mesh = self.meshes.items[handle];
                var mesh_node: vk.Node = .{
                    .material = mesh.surfaces.items[0].material,
                    .mesh = &mesh,
                    .local_transform = .fromMat4x4(.identity),
                    .world_transform = .fromMat4x4(.identity),
                };
                try mesh_node.draw(self.allocator, transform, &self.main_draw_context);
            },
            .gltf => |handle| {
                var structure_scene = self.loaded_scenes.items[handle];
                try structure_scene.draw(self.allocator, transform, &self.main_draw_context);
                //TODO: fix ur shit. Transparent pipelines are broken.
            },
        }

        drawGeometry(self, self.main_draw_context.opaque_surfaces, cmd_buffer, globalDescriptor);
        drawGeometry(self, self.main_draw_context.transparent_surfaces, cmd_buffer, globalDescriptor);
    }

    var draw_debug_query = world.query(&.{ WorldModule.Collider, nz.Transform3D(f32) });
    while (draw_debug_query.next()) |entry| {
        self.main_draw_context.clear();
        const transform = entry.get(nz.Transform3D(f32), world).?;
        const collider = entry.get(WorldModule.Collider, world).?;
        self.last_index_buffer = null;
        self.last_material = null;
        self.last_pipeline = null;
        switch (collider.shape) {
            .primitive => |shape| {
                switch (shape) {
                    .box => {
                        var mesh = self.debug_meshes[0];
                        var mesh_node: vk.Node = .{
                            .material = mesh.surfaces.items[0].material,
                            .mesh = &mesh,
                            .local_transform = .fromMat4x4(.identity),
                            .world_transform = .fromMat4x4(.identity),
                        };
                        try mesh_node.draw(self.allocator, transform, &self.main_draw_context);
                    },
                    .capsule => {},
                    .sphere => {},
                }
            },
            .complex => {},
        }
        drawGeometry(self, self.main_draw_context.opaque_surfaces, cmd_buffer, globalDescriptor);
    }
    vk.c.vkCmdEndRendering(cmd_buffer);

    draw_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, vk.c.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.c.VK_ACCESS_TRANSFER_READ_BIT);

    var swapchain_image_barrier: vk.ImageBarrier = .init(cmd_buffer, self.swapchain.vk_images[image_index], vk.c.VK_IMAGE_ASPECT_COLOR_BIT);
    swapchain_image_barrier.transition(vk.c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.c.VK_PIPELINE_STAGE_TRANSFER_BIT, vk.c.VK_ACCESS_TRANSFER_WRITE_BIT);
    self.draw_image.copyOntoImage(
        cmd_buffer,
        .{ .vk_image = self.swapchain.vk_images[image_index], .extent = self.swapchain.extent },
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
        return;
    }

    self.swapchain.current_frame_inflight += 1;
}

fn drawGeometry(
    self: *@This(),
    render_objects: std.ArrayList(vk.Node.RenderObject),
    cmd_buffer: vk.c.VkCommandBuffer,
    globalDescriptor: vk.c.VkDescriptorSet,
) void {
    for (render_objects.items[0..render_objects.items.len]) |render_obj| {
        // if (render_obj.isVisible(.new(self.scene_data.viewproj)) == false) continue;
        if (render_obj.material_instance != self.last_material) {
            self.last_material = render_obj.material_instance;

            if (render_obj.material_instance.pipeline != self.last_pipeline) {
                self.last_pipeline = render_obj.material_instance.pipeline;

                vk.c.vkCmdBindPipeline(cmd_buffer, vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS, render_obj.material_instance.pipeline.graphics.handle);

                vk.c.vkCmdBindDescriptorSets(
                    cmd_buffer,
                    vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                    render_obj.material_instance.pipeline.get().layout,
                    0,
                    1,
                    &globalDescriptor,
                    0,
                    null,
                );

                var viewport: vk.c.VkViewport = .{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(self.draw_image.extent.width),
                    .height = @floatFromInt(self.draw_image.extent.height),
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
                        .width = self.draw_image.extent.width,
                        .height = self.draw_image.extent.height,
                    },
                };

                vk.c.vkCmdSetScissor(cmd_buffer, 0, 1, &scissor);
            }
            vk.c.vkCmdBindDescriptorSets(
                cmd_buffer,
                vk.c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                render_obj.material_instance.pipeline.get().layout,
                1,
                1,
                &render_obj.material_instance.descriptor_set,
                0,
                null,
            );
        }
        if (render_obj.index_buffer != self.last_index_buffer) {
            self.last_index_buffer = render_obj.index_buffer;
            vk.c.vkCmdBindIndexBuffer(cmd_buffer, render_obj.index_buffer, 0, vk.c.VK_INDEX_TYPE_UINT32);
        }

        var push_constant: vk.Mesh.GPUDrawPushConstants = .{
            .world_matrix = render_obj.transform.toMat4x4().d,
            .vertex_buffer = render_obj.vertex_buffer_address,
        };

        vk.c.vkCmdPushConstants(cmd_buffer, render_obj.material_instance.pipeline.get().layout, vk.c.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(vk.Mesh.GPUDrawPushConstants), &push_constant);

        vk.c.vkCmdDrawIndexed(cmd_buffer, render_obj.index_count, 1, render_obj.first_index, 0, 0);
    }
}

pub fn createMesh(self: *@This(), name: []const u8, indices: []u32, verices: []vk.Mesh.Vertex) !usize {
    const mesh = try vk.Mesh.init(
        self.allocator,
        self.vma.handle,
        name,
        self.device,
        &.{.{
            .index_start = 0,
            .index_count = @intCast(indices.len),
            .bounds = .{ .origin = @splat(0), .sphere_radius = 0, .extents = @splat(1) },
            .material = self.default_data,
        }},
        indices,
        verices,
    );
    try self.meshes.append(
        self.allocator,
        mesh,
    );

    return (self.meshes.items.len - 1);
}

pub fn loadGltf(self: *@This(), path: []const u8) !usize {
    const strcture_file = try LoadedGltf.init(
        self.allocator,
        self.vma,
        self.device,
        path,
        .{ self.error_checkerboard_image, self.white_image },
        self.default_sampler_linear,
        &self.metal_rough_material,
    );
    try self.loaded_scenes.append(self.allocator, strcture_file);
    return self.loaded_scenes.items.len - 1;
}

pub fn getViewMatrix(transform: *const nz.Transform3D(f32)) nz.Mat4x4(f32) {
    // const forward = nz.vec.forwardFromEuler(transform.rotation);
    // return nz.Mat4x4(f32).lookAt(transform.position, transform.position + forward, .{ 0, 1, 0 });
    var camera_translation = nz.Mat4x4(f32).translate(transform.position);
    const camera_rotation = getRotationMatrix(transform);
    return (camera_translation.mul(camera_rotation)).inverse();
}

pub fn getRotationMatrix(transform: *const nz.Transform3D(f32)) nz.Mat4x4(f32) {
    const pitch_rotation: nz.quat.Hamiltonian(f32) = .angleAxis(transform.rotation[0], .{ 1, 0, 0 });
    const yaw_rotation: nz.quat.Hamiltonian(f32) = .angleAxis(transform.rotation[1], .{ 0, -1, 0 });

    return yaw_rotation.mul(pitch_rotation).toMat4x4().inverse();
}
pub fn perspective(fovy_rad: f32, aspect: f32, near: f32, far: f32) nz.Mat4x4(f32) {
    const f = 1.0 / std.math.tan(fovy_rad / 2.0);
    return .new(.{
        f / aspect, 0, 0, 0,
        0, -f, 0, 0, // flip Y for Vulkan
        0, 0, far / (near - far),          -1, // <- note near-far here
        0, 0, (far * near) / (near - far), 0,
    });
}
