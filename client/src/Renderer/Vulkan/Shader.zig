const std = @import("std");
const c = @import("vulkan");
const shaderc = @import("shaderc");
const AssetServer = @import("shared").AssetServer;
const Device = @import("device.zig").Logical;
const ext = @import("procFunctions.zig").device.ProcTable;
pub const check = @import("utils.zig").check;

pub const PushConstant = extern struct {
    model_matrix: [16]f32,
    buffer_address: c.VkDeviceAddress,
};

device: Device,
shader_create_info: c.VkShaderCreateInfoEXT,
shader_name: []const u8,
handle: c.VkShaderEXT = null,

pub fn init(allocator: std.mem.Allocator, device: Device, asset_server: *AssetServer, sahder_create_info: c.VkShaderCreateInfoEXT, shader_name: []const u8) !*@This() {
    const self = try allocator.create(@This());
    self.device = device;
    self.shader_create_info = sahder_create_info;
    self.shader_name = shader_name;
    self.handle = null;
    try asset_server.loadAsset(@This(), self, shader_name, loadShader);
    return self;
}
pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    ext.vkDestroyShaderEXT(self.device.handle, self.handle, null);
    self.* = undefined;
    allocator.destroy(self);
}

fn loadShader(user_data: *anyopaque, path: []const u8, io: std.Io, allocator: std.mem.Allocator, file: std.Io.File) !void {
    _ = path;
    const self: *@This() = @ptrCast(@alignCast(user_data));
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    const content = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(content);
    std.debug.print("size:  {d}\n", .{content.len});

    const compiler = shaderc.shaderc_compiler_initialize();
    defer shaderc.shaderc_compiler_release(compiler);
    const ranges: c.VkPushConstantRange = .{
        .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = @sizeOf(PushConstant),
    };
    const shader_kind: c_uint = switch (self.shader_create_info.stage) {
        c.VK_SHADER_STAGE_VERTEX_BIT => shaderc.shaderc_glsl_vertex_shader,
        c.VK_SHADER_STAGE_FRAGMENT_BIT => shaderc.shaderc_glsl_fragment_shader,
        else => unreachable,
    };

    //TODO: Trim the name out of the path instead.
    const shader_name: []const u8 = switch (self.shader_create_info.stage) {
        c.VK_SHADER_STAGE_VERTEX_BIT => "vertex.vert",
        c.VK_SHADER_STAGE_FRAGMENT_BIT => "fragment.frag",
        else => unreachable,
    };
    const result = shaderc.shaderc_compile_into_spv(
        compiler,
        content.ptr,
        content.len,
        shader_kind,
        shader_name.ptr,
        "main",
        null,
    );
    defer shaderc.shaderc_result_release(result);
    const status = shaderc.shaderc_result_get_compilation_status(result);
    std.debug.print("result code {d}\n", .{status});
    if (status != shaderc.shaderc_compilation_status_success) {
        std.debug.print("err message {s}\n", .{shaderc.shaderc_result_get_error_message(result)});
        return;
    }
    const data = shaderc.shaderc_result_get_bytes(result);
    const len = shaderc.shaderc_result_get_length(result);
    // std.debug.print("size:  {d}\n", .{len});
    // std.debug.print("data:  {s}\n", .{data});

    self.shader_create_info.pPushConstantRanges = &ranges;
    self.shader_create_info.codeSize = len;
    self.shader_create_info.pCode = data;
    if (self.handle != null) ext.vkDestroyShaderEXT(self.device.handle, self.handle, null);
    try check(ext.vkCreateShadersEXT(self.device.handle, 1, &self.shader_create_info, null, &self.handle));
}
