const std = @import("std");
const nz = @import("numz");

pub const Rigidbody = struct {
    force: nz.Vec3(f32) = @splat(0.0),
    mass: f32 = 1.0,
};
