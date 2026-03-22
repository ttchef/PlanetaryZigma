const Vertex = @import("../Mesh.zig").Vertex;

pub const vertex_array = [_]Vertex{
    // Front (+Z)
    .{ .position = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 0, 0, 1 }, .uv_x = 0, .uv_y = 1 },
    .{ .position = .{ 0.5, -0.5, 0.5 }, .color = .{ 0, 1, 0, 1 }, .uv_x = 1, .uv_y = 1 },
    .{ .position = .{ -0.5, 0.5, 0.5 }, .color = .{ 0, 0, 1, 1 }, .uv_x = 0, .uv_y = 0 },
    .{ .position = .{ 0.5, 0.5, 0.5 }, .color = .{ 1, 1, 0, 1 }, .uv_x = 1, .uv_y = 0 },

    // Back (-Z)
    .{ .position = .{ 0.5, -0.5, -0.5 }, .color = .{ 1, 0, 1, 1 }, .uv_x = 0, .uv_y = 1 },
    .{ .position = .{ -0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1, 1 }, .uv_x = 1, .uv_y = 1 },
    .{ .position = .{ 0.5, 0.5, -0.5 }, .color = .{ 1, 1, 1, 1 }, .uv_x = 0, .uv_y = 0 },
    .{ .position = .{ -0.5, 0.5, -0.5 }, .color = .{ 0, 0, 0, 1 }, .uv_x = 1, .uv_y = 0 },

    // Left (-X)
    .{ .position = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 0, 0, 1 }, .uv_x = 0, .uv_y = 1 },
    .{ .position = .{ -0.5, -0.5, 0.5 }, .color = .{ 0, 1, 0, 1 }, .uv_x = 1, .uv_y = 1 },
    .{ .position = .{ -0.5, 0.5, -0.5 }, .color = .{ 0, 0, 1, 1 }, .uv_x = 0, .uv_y = 0 },
    .{ .position = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 1, 0, 1 }, .uv_x = 1, .uv_y = 0 },

    // Right (+X)
    .{ .position = .{ 0.5, -0.5, 0.5 }, .color = .{ 1, 0, 1, 1 }, .uv_x = 0, .uv_y = 1 },
    .{ .position = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1, 1 }, .uv_x = 1, .uv_y = 1 },
    .{ .position = .{ 0.5, 0.5, 0.5 }, .color = .{ 1, 1, 1, 1 }, .uv_x = 0, .uv_y = 0 },
    .{ .position = .{ 0.5, 0.5, -0.5 }, .color = .{ 0, 0, 0, 1 }, .uv_x = 1, .uv_y = 0 },

    // Top (+Y)
    .{ .position = .{ -0.5, 0.5, 0.5 }, .color = .{ 1, 0, 0, 1 }, .uv_x = 0, .uv_y = 1 },
    .{ .position = .{ 0.5, 0.5, 0.5 }, .color = .{ 0, 1, 0, 1 }, .uv_x = 1, .uv_y = 1 },
    .{ .position = .{ -0.5, 0.5, -0.5 }, .color = .{ 0, 0, 1, 1 }, .uv_x = 0, .uv_y = 0 },
    .{ .position = .{ 0.5, 0.5, -0.5 }, .color = .{ 1, 1, 0, 1 }, .uv_x = 1, .uv_y = 0 },

    // Bottom (-Y)
    .{ .position = .{ -0.5, -0.5, -0.5 }, .color = .{ 1, 0, 1, 1 }, .uv_x = 0, .uv_y = 1 },
    .{ .position = .{ 0.5, -0.5, -0.5 }, .color = .{ 0, 1, 1, 1 }, .uv_x = 1, .uv_y = 1 },
    .{ .position = .{ -0.5, -0.5, 0.5 }, .color = .{ 1, 1, 1, 1 }, .uv_x = 0, .uv_y = 0 },
    .{ .position = .{ 0.5, -0.5, 0.5 }, .color = .{ 0, 0, 0, 1 }, .uv_x = 1, .uv_y = 0 },
};

pub const indicies_array = [_]u32{
    // Front
    0,  1,  2,  1,  3,  2,
    // Back
    4,  5,  6,  5,  7,  6,
    // Left
    8,  9,  10, 9,  11, 10,
    // Right
    12, 13, 14, 13, 15, 14,
    // Top
    16, 17, 18, 17, 19, 18,
    // Bottom
    20, 21, 22, 21, 23, 22,
};
