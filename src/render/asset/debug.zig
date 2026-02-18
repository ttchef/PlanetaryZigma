const std = @import("std");
const nz = @import("numz");
const vk = @import("../vulkan/vulkan.zig");

pub const line_amount: u32 = 100;

pub const Info = struct {
    seconds_alive: f32,
    index_handle: usize,
};

pub const Point = extern struct {
    position: [3]f32,
    color: nz.color.Rgba(u8),
};

pub const Line = extern struct {
    from: Point,
    to: Point,
};

pub const collider = struct {
    pub const Config = struct {
        allocator: std.mem.Allocator,
        vma: vk.Vma,
        device: vk.Device,
        material: *vk.Material.Instance,
    };
    pub fn createBox(config: Config) !vk.Mesh {
        const white = nz.color.Rgba(u8).white;

        const yellow = nz.color.Rgba(u8).yellow;

        // 8 corners of a cube :D
        var vertices = [_][4](f32){
            .{ -1, -1, -1, @bitCast(white) }, // 0
            .{ 1, -1, -1, @bitCast(white) }, // 1
            .{ 1, 1, -1, @bitCast(white) }, // 2
            .{ -1, 1, -1, @bitCast(white) }, // 3
            .{ -1, -1, 1, @bitCast(yellow) }, // 4
            .{ 1, -1, 1, @bitCast(yellow) }, // 5
            .{ 1, 1, 1, @bitCast(yellow) }, // 6
            .{ -1, 1, 1, @bitCast(yellow) }, // 7
        };

        var indices = [_]u32{
            0, 1, 2, 2, 3, 0, // back
            4, 5, 6, 6, 7, 4, // front
            0, 4, 7, 7, 3, 0, // left
            1, 5, 6, 6, 2, 1, // right
            0, 1, 5, 5, 4, 0, // bottom
            3, 2, 6, 6, 7, 3, // top
        };

        const mesh: vk.Mesh = try .init(
            config.allocator,
            config.vma.handle,
            "Box",
            config.device,
            &.{.{
                .index_start = 0,
                .index_count = @intCast(indices.len),
                .bounds = .{ .origin = @splat(0), .sphere_radius = 0, .extents = @splat(1) },
                .material = config.material,
            }},
            indices[0..],
            [4]f32,
            vertices[0..],
        );
        return mesh;
    }
    fn pushTri(allocator: std.mem.Allocator, indices: *std.ArrayList(u32), a: u32, b: u32, c: u32) !void {
        try indices.append(allocator, a);
        try indices.append(allocator, b);
        try indices.append(allocator, c);
    }

    pub fn createSphereMesh(
        config: Config,
        radius: f32,
    ) !vk.Mesh {
        var verts: std.ArrayList([4]f32) = .empty;
        var indices: std.ArrayList(u32) = .empty;
        const color: nz.color.Rgba(u8) = .white;
        errdefer verts.deinit(config.allocator);
        errdefer indices.deinit(config.allocator);

        const pi = std.math.pi;
        const two_pi = 2.0 * pi;

        // rings+1 by slices+1 grid (duplicate seam)
        var r: u32 = 0;
        const rings: usize = 10;
        const slices: usize = 10;
        while (r <= rings) : (r += 1) {
            const v = @as(f32, @floatFromInt(r)) / @as(f32, @floatFromInt(rings)); // 0..1
            const phi = v * pi; // 0..pi
            const y = std.math.cos(phi) * radius;
            const sin_phi = std.math.sin(phi);

            var s: u32 = 0;
            while (s <= slices) : (s += 1) {
                const u = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(slices)); // 0..1
                const theta = u * two_pi; // 0..2pi

                const x = std.math.cos(theta) * sin_phi * radius;
                const z = std.math.sin(theta) * sin_phi * radius;

                try verts.append(config.allocator, .{ x, y, z, @bitCast(color) });
            }
        }

        const stride = slices + 1;
        r = 0;
        while (r < rings) : (r += 1) {
            var s: u32 = 0;
            while (s < slices) : (s += 1) {
                const i_0: u32 = r * @as(u32, @intCast(stride)) + s;
                const i_1: u32 = i_0 + 1;
                const i_2: u32 = (r + 1) * @as(u32, @intCast(stride)) + s;
                const i_3: u32 = i_2 + 1;

                // two triangles per quad (consistent winding)
                try pushTri(config.allocator, &indices, i_0, i_2, i_1);
                try pushTri(config.allocator, &indices, i_1, i_2, i_3);
            }
        }

        const mesh: vk.Mesh = try .init(
            config.allocator,
            config.vma.handle,
            "Box",
            config.device,
            &.{.{
                .index_start = 0,
                .index_count = @intCast(indices.items.len),
                .bounds = .{ .origin = @splat(0), .sphere_radius = 0, .extents = @splat(1) },
                .material = config.material,
            }},
            indices.items[0..],
            [4]f32,
            verts.items[0..],
        );
        return mesh;
    }

    pub fn createCapsuleMesh(
        config: Config,
        radius: f32,
        half_height: f32,
    ) !vk.Mesh {
        const hemi_rings: usize = 10;
        const slices: usize = 10;
        const color: nz.color.Rgba(u8) = .white;
        var verts: std.ArrayList([4]f32) = .empty;
        var indices: std.ArrayList(u32) = .empty;
        errdefer verts.deinit(config.allocator);
        errdefer indices.deinit(config.allocator);

        const pi = std.math.pi;
        const two_pi = 2.0 * pi;

        const stacks: u32 = 2 * hemi_rings + 2;
        const stride = slices + 1;

        var st: u32 = 0;
        while (st <= stacks) : (st += 1) {
            const t = @as(f32, @floatFromInt(st)) / @as(f32, @floatFromInt(stacks)); // 0..1
            const phi = t * pi;
            const cos_phi = std.math.cos(phi);
            const sin_phi = std.math.sin(phi);

            const sphere_y = cos_phi * radius;
            const ring_r = sin_phi * radius;

            const y: f32 = if (phi < (pi * 0.5))
                sphere_y + half_height
            else
                sphere_y - half_height;

            var s: u32 = 0;
            while (s <= slices) : (s += 1) {
                const u = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(slices));
                const theta = u * two_pi;

                const x = std.math.cos(theta) * ring_r;
                const z = std.math.sin(theta) * ring_r;

                try verts.append(config.allocator, .{ x, y, z, @bitCast(color) });
            }
        }
        st = 0;
        while (st < stacks) : (st += 1) {
            var s: u32 = 0;
            while (s < slices) : (s += 1) {
                const i_0: u32 = st * @as(u32, @intCast(stride)) + s;
                const i_1: u32 = i_0 + 1;
                const i_2: u32 = (st + 1) * @as(u32, @intCast(stride)) + s;
                const i_3: u32 = i_2 + 1;

                try pushTri(config.allocator, &indices, i_0, i_2, i_1);
                try pushTri(config.allocator, &indices, i_1, i_2, i_3);
            }
        }

        const mesh: vk.Mesh = try .init(
            config.allocator,
            config.vma.handle,
            "Box",
            config.device,
            &.{.{
                .index_start = 0,
                .index_count = @intCast(indices.items.len),
                .bounds = .{ .origin = @splat(0), .sphere_radius = 0, .extents = @splat(1) },
                .material = config.material,
            }},
            indices.items[0..],
            [4]f32,
            verts.items[0..],
        );
        return mesh;
    }
};
