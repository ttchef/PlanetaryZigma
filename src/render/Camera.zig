const std = @import("std");
const nz = @import("numz");
const sdl = @import("sdl");

fov_rad: f32 = 1.5,
aspect: f32 = 0,
near: f32 = 0,
far: f32 = 1000,
speed: f32 = 0.5,
sensitivity: f32 = 0.05,
was_rotating: bool = false,

pub fn getViewMatrix(transform: *const nz.Transform3D(f32)) nz.Mat4x4(f32) {
    var camera_translation = nz.Mat4x4(f32).translate(transform.position);
    const camera_rotation = getRotationMatrix(transform);
    return (camera_translation.mul(camera_rotation)).inverse();
}

pub fn getRotationMatrix(transform: *const nz.Transform3D(f32)) nz.Mat4x4(f32) {
    const pitch_rotation: nz.quat.Hamiltonian(f32) = .angleAxis(transform.rotation[0], .{ 1, 0, 0 });
    const yaw_rotation: nz.quat.Hamiltonian(f32) = .angleAxis(transform.rotation[1], .{ 0, -1, 0 });

    return nz.Mat4x4(f32).fromQuaternion(yaw_rotation.toVec()).mul(nz.Mat4x4(f32).fromQuaternion(pitch_rotation.toVec()));
}
