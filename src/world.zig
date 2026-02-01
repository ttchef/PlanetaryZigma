const std = @import("std");
const zphy = @import("zphysics");
const ecs = @import("ecs");
const nz = @import("numz");

pub const World = ecs.World(&.{
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
    const Complex = struct {
        indices: std.ArrayList(u32),
        // vertices: std.ArrayList(Vertex),
    };
    quat: nz.quat.Hamiltonian(f32) = .identity,
    z_phycis_body: zphy.BodyId = undefined,
    shape: union(enum) { primitive: Primitive, complex: Complex },
};

pub const Camera = struct {
    fov_rad: f32 = 1.5,
    aspect: f32 = 0,
    near: f32 = 0.1,
    far: f32 = 1000,
    speed: f32 = 10,
    sensitivity: f32 = 0.5,
    was_rotating: bool = false,
};

pub const Model = struct {
    model: union(enum) { gltf: usize, mesh: usize },
};
