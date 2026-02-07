const std = @import("std");
const zphy = @import("zphysics");
const ec = @import("ec");
const nz = @import("numz");

pub const World = ec.World(&.{
    nz.Transform3D(f32),
    Camera,
    Player,
    Model,
    Collider,
});

pub const Player = struct {
    local: bool = false,
};

pub const Collider = struct {
    const Primitive = enum {
        capsule,
        box,
        sphere,
    };
    const Mesh = struct {
        indices: std.ArrayList(u32),
        vertices: std.ArrayList(nz.Vec3(f32)),
    };
    body_id: zphy.BodyId = undefined,
    max_angular_velocity: f32 = 1,
    shape: union(enum) { primitive: Primitive, mesh: Mesh },
};

pub const Camera = struct {
    fov_rad: f32 = 1.5,
    aspect: f32 = 0,
    near: f32 = 0.1,
    far: f32 = 1000,
    speed: f32 = 500,
    sensitivity: f32 = 1,
    was_rotating: bool = false,
};

pub const Model = struct {
    model: union(enum) { gltf: usize, mesh: usize },
};
